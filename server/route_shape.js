'use strict';

/**
 * Route polylines from the DSAT open-data shapefiles.
 *
 *   BUS_ROUTE_SEQ.ROUTE_NOS  -> which route
 *   BUS_ROUTE_SEQ.NETWORK_ID -> ROUTE_NETWORK geometry, in sequence order
 *
 * BUS_POLE is the stop layer already used by the existing server. This module
 * does not read it and does not call motransportinfo.
 *
 * Drop-in for the Oracle host. See server/ORACLE_DEPLOY.md.
 */

const fs = require('fs');
const path = require('path');
const proj4 = require('proj4');

const MACAU_GRID = '+proj=tmerc +lat_0=22.21239722222222 +lon_0=113.5364694444444 +k=1.0 +x_0=20000 +y_0=20000 +ellps=intl +towgs84=-162.619,-273.963,-187.095 +units=m +no_defs';
const WGS84 = proj4.WGS84;
const MACAU_LAT_OFFSET = 0.00034;
const MACAU_LNG_OFFSET = 0.00048;

const ATTRIBUTION = '澳門特別行政區政府數據開放平台';
const DEFAULT_DATA_DATE = '2026-09-25';

const ROUTE_FIELDS = ['ROUTE_NOS', 'ROUTE_NO', 'ROUTENO', 'ROUTE', 'ROUTE_CODE'];
const NETWORK_ID_FIELDS = ['NETWORK_ID', 'NET_ID', 'EDGE_ID', 'EDGEID', 'ID'];
const SEQ_FIELDS = ['SEQ', 'SEQUENCE', 'SEQ_NO', 'ROUTE_SEQ', 'ORDER_NO', 'SORT_NO', 'SEQNO'];
const DIR_FIELDS = ['DIR', 'DIRECTION', 'DIRECT', 'WAY', 'UPDOWN', 'BOUND', 'ROUTE_DIR', 'DIR_CD'];

function normId(value) {
  if (value == null) return '';
  const s = String(value).trim();
  if (/^[+-]?\d+\.0+$/.test(s)) return String(parseInt(s, 10));
  return s;
}

function upper(value) {
  return String(value ?? '').trim().toUpperCase();
}

function routeMatches(value, route) {
  const want = upper(route);
  if (!want) return false;
  const raw = upper(value);
  if (raw === want) return true;
  return raw.split(/[,，;；/|、\s]+/).filter(Boolean).includes(want);
}

function pickField(names, candidates) {
  const set = new Map(names.map((n) => [upper(n), n]));
  for (const candidate of candidates) {
    if (set.has(candidate)) return set.get(candidate);
  }
  return null;
}

function fieldValue(row, fieldName) {
  if (!fieldName) return undefined;
  return row.fields[fieldName];
}

function looksLikeLng(v) {
  return v >= 113.3 && v <= 113.8;
}

function looksLikeLat(v) {
  return v >= 22.0 && v <= 22.3;
}

function readDbf(filePath) {
  const buf = fs.readFileSync(filePath);
  const recordCount = buf.readUInt32LE(4);
  const headerLen = buf.readUInt16LE(8);
  const recordLen = buf.readUInt16LE(10);
  const fields = [];
  let pos = 32;
  while (pos + 32 <= headerLen) {
    if (buf[pos] === 0x0d) break;
    const name = buf.slice(pos, pos + 11).toString('ascii').replace(/\0.*$/, '').trim();
    const type = String.fromCharCode(buf[pos + 11]);
    const size = buf[pos + 16];
    const dec = buf[pos + 17];
    if (!name || size <= 0) break;
    fields.push({ name, type, size, dec });
    pos += 32;
  }

  const rows = [];
  for (let i = 0; i < recordCount; i++) {
    const off = headerLen + i * recordLen;
    if (off + recordLen > buf.length) break;
    const deleted = buf[off] === 0x2a;
    const values = {};
    let cursor = off + 1;
    for (const field of fields) {
      const raw = buf.slice(cursor, cursor + field.size).toString('latin1');
      cursor += field.size;
      const text = raw.replace(/\0/g, '').trim();
      if (field.type === 'N' || field.type === 'F') {
        values[field.name] = text === '' ? null : Number(text);
      } else {
        values[field.name] = text;
      }
    }
    rows.push({
      deleted,
      fields: values,
      recordNumber: i + 1,
    });
  }
  return { fields: fields.map((f) => f.name), rows };
}

function readShpRings(filePath) {
  const buf = fs.readFileSync(filePath);
  if (buf.length < 100) return [];
  const fileCode = buf.readInt32BE(0);
  if (fileCode !== 9994) {
    throw new Error(`not a shapefile: ${filePath}`);
  }
  const ringsByRecord = [];
  let offset = 100;
  while (offset + 8 <= buf.length) {
    const contentWords = buf.readInt32BE(offset + 4);
    const contentBytes = contentWords * 2;
    const start = offset + 8;
    const end = start + contentBytes;
    if (end > buf.length) break;
    ringsByRecord.push(parsePolyRecord(buf, start, end));
    offset = end;
  }
  return ringsByRecord;
}

function parsePolyRecord(buf, start, end) {
  if (start + 44 > end) return [];
  const type = buf.readInt32LE(start);
  if (type === 0) return [];
  if (![3, 5, 13, 15, 23, 25].includes(type)) return [];
  let p = start + 4 + 32;
  if (p + 8 > end) return [];
  const numParts = buf.readInt32LE(p);
  p += 4;
  const numPoints = buf.readInt32LE(p);
  p += 4;
  if (numParts < 0 || numPoints < 0) return [];
  if (p + numParts * 4 + numPoints * 16 > end) return [];
  const parts = [];
  for (let i = 0; i < numParts; i++) {
    parts.push(buf.readInt32LE(p));
    p += 4;
  }
  const xy = [];
  for (let i = 0; i < numPoints; i++) {
    const x = buf.readDoubleLE(p);
    p += 8;
    const y = buf.readDoubleLE(p);
    p += 8;
    xy.push([x, y]);
  }
  const rings = [];
  for (let i = 0; i < parts.length; i++) {
    const a = parts[i];
    const b = i + 1 < parts.length ? parts[i + 1] : xy.length;
    if (b > a) rings.push(xy.slice(a, b));
  }
  return rings;
}

function findLayer(shapeDir, baseName) {
  const entries = fs.readdirSync(shapeDir);
  const match = entries.find((name) => upper(path.parse(name).name) === baseName && upper(path.extname(name)) === '.DBF');
  if (!match) return null;
  const stem = path.join(shapeDir, path.parse(match).name);
  return {
    dbf: `${stem}.dbf`.replace(/\.dbf$/i, '.dbf') && fs.existsSync(`${stem}.dbf`)
      ? `${stem}.dbf`
      : path.join(shapeDir, match),
    shp: [`${stem}.shp`, `${stem}.SHP`].find((p) => fs.existsSync(p)) || null,
    prj: [`${stem}.prj`, `${stem}.PRJ`].find((p) => fs.existsSync(p)) || null,
  };
}

function loadTable(shapeDir, baseName) {
  const found = findLayer(shapeDir, baseName);
  if (!found) return null;
  const dbf = readDbf(found.dbf);
  const rings = found.shp ? readShpRings(found.shp) : [];
  const rows = dbf.rows.map((row, i) => ({
    ...row,
    rings: rings[i] || [],
  }));
  return {
    baseName,
    fieldNames: dbf.fields,
    rows,
    prj: found.prj ? fs.readFileSync(found.prj, 'utf8') : '',
    shp: found.shp,
    dbf: found.dbf,
  };
}

function indexNetwork(table) {
  const idField = pickField(table.fieldNames, NETWORK_ID_FIELDS);
  const byField = new Map();
  const byRecord = new Map();
  for (const row of table.rows) {
    if (row.deleted) continue;
    byRecord.set(String(row.recordNumber), row);
    if (!idField) continue;
    const key = normId(fieldValue(row, idField));
    if (key && !byField.has(key)) byField.set(key, row);
  }
  return { idField, byField, byRecord };
}

function lookupNetwork(index, id) {
  const key = normId(id);
  if (!key) return null;
  if (index.byField.has(key)) return index.byField.get(key);
  if (index.byRecord.has(key)) return index.byRecord.get(key);
  return null;
}

function directionMapper(values) {
  const uniq = [...new Set(values.map((v) => String(v ?? '').trim()).filter(Boolean))];
  const nums = uniq.map((v) => Number(v));
  if (uniq.length && nums.every((n) => !Number.isNaN(n))) {
    const min = Math.min(...nums);
    return (v) => {
      const n = Number(String(v ?? '').trim());
      return Number.isNaN(n) ? null : n - min;
    };
  }
  return (v) => {
    const s = upper(v);
    if (['0', 'F', 'FORWARD', 'UP', '去', '去程', '上行', 'O'].includes(s)) return 0;
    if (['1', 'B', 'BACKWARD', 'DOWN', '回', '回程', '下行', 'I'].includes(s)) return 1;
    return null;
  };
}

function joinTolerance(pt) {
  if (!pt) return 1e-6;
  const ax = Math.abs(pt[0]);
  const ay = Math.abs(pt[1]);
  // Geographic degrees around Macau, or Macau Grid meters (~20 km origin).
  if (ax <= 180 && ay <= 90) return 2e-4;
  return 20;
}

function nearPoint(a, b, tol) {
  return Math.hypot(a[0] - b[0], a[1] - b[1]) <= tol;
}

/**
 * Walk edges in SEQ order. Flip an edge when its far end is the one that
 * meets the previous vertex. If neither end meets, start another polyline.
 * Disconnected rings are not joined by a straight jump.
 * @returns {number[][][]}
 */
function chainRings(rings) {
  const usable = rings.filter((r) => r && r.length).map((r) => r.slice());
  if (!usable.length) return [];
  const tol = joinTolerance(usable[0][0]);
  if (usable.length >= 2) {
    const a = usable[0];
    const b = usable[1];
    const a0 = a[0];
    const a1 = a[a.length - 1];
    const b0 = b[0];
    const b1 = b[b.length - 1];
    const endTouches = nearPoint(a1, b0, tol) || nearPoint(a1, b1, tol);
    const startTouches = nearPoint(a0, b0, tol) || nearPoint(a0, b1, tol);
    if (!endTouches && startTouches) usable[0] = a.slice().reverse();
  }
  const lines = [];
  let current = [];
  for (const ring of usable) {
    if (!current.length) {
      current = ring.slice();
      continue;
    }
    const last = current[current.length - 1];
    let pts = ring;
    let joined = false;
    if (nearPoint(last, ring[0], tol)) {
      joined = true;
    } else if (nearPoint(last, ring[ring.length - 1], tol)) {
      pts = ring.slice().reverse();
      joined = true;
    }
    if (!joined) {
      if (current.length >= 2) lines.push(current);
      current = ring.slice();
      continue;
    }
    const start = nearPoint(current[current.length - 1], pts[0], tol) ? 1 : 0;
    for (let i = start; i < pts.length; i++) current.push(pts[i]);
  }
  if (current.length >= 2) lines.push(current);
  return lines;
}

function metersBetween(a, b) {
  const dy = b.lat - a.lat;
  const dx = (b.lng - a.lng) * Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
  return Math.hypot(dy, dx) * 111320;
}

function bearingDeg(a, b) {
  const dy = b.lat - a.lat;
  const dx = (b.lng - a.lng) * Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
  return (Math.atan2(dx, dy) * 180 / Math.PI + 360) % 360;
}

function angleDiff(a, b) {
  const d = Math.abs(a - b) % 360;
  return Math.min(d, 360 - d);
}

/**
 * Drop steps that are not road edges so the map never strokes them.
 * A step ≥ 600 m breaks when it turns off the local bearing or sits
 * between two short neighbors. Colinear bridge spans (N3's ~800 m
 * steps) stay. A step ≥ 160 m that reverses within 400 m is a landfill
 * zigzag and both legs are dropped. A step ≥ 250 m with a teleport on
 * one side and no long colinear continuation is a chord across a gap
 * (the westbound water stroke on route 102) and is dropped. A lone
 * 2-point edge has nothing to compare and stays.
 * @param {{lat:number,lng:number}[]} points
 * @returns {{lat:number,lng:number}[][]}
 */
function splitDiscontinuous(points) {
  if (!points || points.length < 2) return [];
  const cap = 600;
  const maxTurn = 30;
  const neighMin = 8;
  const reverseMin = 160;
  const reverseTurn = 120;
  const maxConn = 400;
  const isolateMin = 250;
  const contBar = 80;
  const ds = [];
  const bs = [];
  for (let i = 1; i < points.length; i++) {
    ds.push(metersBetween(points[i - 1], points[i]));
    bs.push(bearingDeg(points[i - 1], points[i]));
  }
  function neigh(start, step) {
    let j = start;
    while (j >= 0 && j < ds.length) {
      if (ds[j] >= neighMin) return { bearing: bs[j], dist: ds[j] };
      j += step;
    }
    return null;
  }
  const breakAfter = new Array(ds.length).fill(false);
  for (let i = 0; i < ds.length; i++) {
    const d = ds[i];
    if (d < cap) continue;
    const prev = neigh(i - 1, -1);
    const next = neigh(i + 1, 1);
    // A missing side is not a turn and is not short, so a lone edge stays.
    const badP = prev ? angleDiff(bs[i], prev.bearing) > maxTurn : false;
    const badN = next ? angleDiff(bs[i], next.bearing) > maxTurn : false;
    const shortP = Boolean(prev) && prev.dist < cap * 0.5;
    const shortN = Boolean(next) && next.dist < cap * 0.5;
    if (badP || badN || (shortP && shortN)) breakAfter[i] = true;
  }
  const longs = [];
  for (let i = 0; i < ds.length; i++) if (ds[i] >= reverseMin) longs.push(i);
  for (let k = 1; k < longs.length; k++) {
    const a = longs[k - 1];
    const b = longs[k];
    let conn = 0;
    for (let j = a + 1; j < b; j++) conn += ds[j];
    if (conn <= maxConn && angleDiff(bs[a], bs[b]) > reverseTurn) {
      breakAfter[a] = true;
      breakAfter[b] = true;
    }
  }
  for (let i = 0; i < ds.length; i++) {
    if (ds[i] < isolateMin || breakAfter[i]) continue;
    const prev = neigh(i - 1, -1);
    const next = neigh(i + 1, 1);
    if (!prev && !next) continue;
    const turnP = prev ? angleDiff(bs[i], prev.bearing) : null;
    const turnN = next ? angleDiff(bs[i], next.bearing) : null;
    const gapP = !prev || (prev.dist >= cap && turnP > maxTurn);
    const gapN = !next || (next.dist >= cap && turnN > maxTurn);
    const contP = Boolean(prev) && turnP <= maxTurn && prev.dist >= contBar;
    const contN = Boolean(next) && turnN <= maxTurn && next.dist >= contBar;
    if ((gapP || gapN) && !contP && !contN) breakAfter[i] = true;
  }
  const lines = [];
  let cur = [points[0]];
  for (let i = 0; i < ds.length; i++) {
    if (breakAfter[i]) {
      if (cur.length >= 2) lines.push(cur);
      cur = [points[i + 1]];
    } else {
      cur.push(points[i + 1]);
    }
  }
  if (cur.length >= 2) lines.push(cur);
  return lines;
}

function toLatLngPoints(xy) {
  if (!xy.length) return { points: [], swapped: false };
  const [x, y] = xy[0];
  let swapped = false;
  if (looksLikeLng(x) && looksLikeLat(y)) {
    swapped = false;
  } else if (looksLikeLat(x) && looksLikeLng(y)) {
    swapped = true;
  } else if (Number.isFinite(x) && Number.isFinite(y) && Math.abs(x) < 1e6 && Math.abs(y) < 1e6) {
    // Macau Grid (ROUTE_NETWORK.prj) -> WGS84, same offsets as BUS_POLE in server.js
    const points = xy.map(([px, py]) => {
      const [lng, lat] = proj4(MACAU_GRID, WGS84, [px, py]);
      return { lat: lat + MACAU_LAT_OFFSET, lng: lng + MACAU_LNG_OFFSET };
    });
    return { points, swapped: false, projected: true };
  } else {
    return { error: 'crs_not_wgs84', sample: { x, y } };
  }
  const points = xy.map(([px, py]) => (
    swapped ? { lat: px, lng: py } : { lat: py, lng: px }
  ));
  return { points, swapped };
}

function orderRows(rows, fields) {
  return rows
    .map((row, index) => ({ row, index, seq: fields.seq ? Number(fieldValue(row, fields.seq)) : index }))
    .sort((a, b) => {
      const as = Number.isFinite(a.seq) ? a.seq : a.index;
      const bs = Number.isFinite(b.seq) ? b.seq : b.index;
      return as - bs || a.index - b.index;
    });
}

function rowsToXyLines(ordered, networkIndex, fields) {
  const rings = [];
  let unmatched = 0;
  for (const item of ordered) {
    const id = fieldValue(item.row, fields.networkId);
    const edge = lookupNetwork(networkIndex, id);
    const edgeRings = edge && edge.rings && edge.rings.length ? edge.rings : item.row.rings;
    if (!edgeRings || !edgeRings.length) {
      unmatched += 1;
      continue;
    }
    for (const ring of edgeRings) rings.push(ring);
  }
  return { rings, unmatched, lines: chainRings(rings) };
}

function projectLines(xyLines) {
  const geoLines = [];
  let swapped = false;
  for (const xy of xyLines) {
    const geo = toLatLngPoints(xy);
    if (geo.error) return geo;
    if (geo.swapped) swapped = true;
    for (const part of splitDiscontinuous(geo.points)) {
      if (part.length >= 2) geoLines.push(part);
    }
  }
  return { lines: geoLines, swapped };
}

function longestLine(lines) {
  return lines.reduce((best, line) => (line.length > best.length ? line : best));
}

function binaryGroups(rows, key) {
  const groups = new Map();
  for (const row of rows) {
    const value = String(fieldValue(row, key) ?? '').trim();
    if (!value) continue;
    if (!groups.has(value)) groups.set(value, []);
    groups.get(value).push(row);
    if (groups.size > 2) return null;
  }
  if (groups.size !== 2) return null;
  return groups;
}

/**
 * When SEQ interleaves two directions, the chain shatters into many pieces.
 * A two-valued column (even if it is not named DIR) is used only when it
 * clearly reconnects the requested direction. Routes that already chain,
 * such as N3, are left alone.
 */
function recoverDirection(rows, networkIndex, fields, dir, baseline) {
  if (!rows.length || baseline.lines.length < 12) return null;
  const skip = new Set([fields.route, fields.networkId, fields.seq, fields.dir].filter(Boolean));
  let best = null;
  for (const key of Object.keys(rows[0].fields || {})) {
    if (skip.has(key)) continue;
    const groups = binaryGroups(rows, key);
    if (!groups) continue;
    const values = [...groups.keys()];
    const mapper = directionMapper(values);
    const mapped = values.map((value) => mapper(value));
    let chosen;
    if (mapped.every((value) => value != null) && new Set(mapped).size === 2) {
      chosen = rows.filter((row) => mapper(fieldValue(row, key)) === dir);
    } else {
      const sorted = values.slice().sort();
      chosen = groups.get(sorted[dir === 1 ? 1 : 0]) || [];
    }
    if (chosen.length < rows.length * 0.25) continue;
    const attempt = rowsToXyLines(orderRows(chosen, fields), networkIndex, fields);
    if (!attempt.lines.length) continue;
    const longer = longestLine(attempt.lines).length > longestLine(baseline.lines).length * 1.4;
    const fewer = attempt.lines.length <= baseline.lines.length / 2;
    if ((longer || fewer) && (!best || attempt.lines.length < best.lines.length)) {
      best = attempt;
    }
  }
  return best;
}

/**
 * Join sequence rows to network edges.
 * @param {object[]} seqRows rows with fields
 * @param {ReturnType<typeof indexNetwork>} networkIndex
 * @param {string} route
 * @param {number} dir
 * @param {object} fields detected column names
 */
function assembleRoute(seqRows, networkIndex, route, dir, fields) {
  const matched = seqRows.filter((row) => !row.deleted && routeMatches(fieldValue(row, fields.route), route));
  if (!matched.length) {
    return { success: false, points: [], lines: [], error: 'no_shape', segmentCount: 0 };
  }

  let chosen = matched;
  if (fields.dir) {
    const mapper = directionMapper(matched.map((row) => fieldValue(row, fields.dir)));
    const tagged = matched.map((row) => ({ row, mapped: mapper(fieldValue(row, fields.dir)) }));
    const distinct = new Set(tagged.map((t) => t.mapped).filter((d) => d != null));
    if (distinct.size > 1) {
      chosen = tagged.filter((t) => t.mapped === dir).map((t) => t.row);
      if (!chosen.length) {
        return { success: false, points: [], lines: [], error: 'no_shape', segmentCount: 0 };
      }
    }
  }

  let built = rowsToXyLines(orderRows(chosen, fields), networkIndex, fields);
  const recovered = recoverDirection(chosen, networkIndex, fields, dir, built);
  if (recovered) built = recovered;
  if (!built.lines.length) {
    return { success: false, points: [], lines: [], error: 'no_shape', segmentCount: built.rings.length, unmatched: built.unmatched };
  }
  const geo = projectLines(built.lines);
  if (geo.error) {
    return { success: false, points: [], lines: [], error: geo.error, sample: geo.sample, segmentCount: built.rings.length };
  }
  if (!geo.lines.length) {
    return { success: false, points: [], lines: [], error: 'no_shape', segmentCount: built.rings.length, unmatched: built.unmatched };
  }
  return {
    success: true,
    points: longestLine(geo.lines),
    lines: geo.lines,
    segmentCount: built.rings.length,
    unmatched: built.unmatched,
    swapped: geo.swapped,
  };
}

class RouteShapeIndex {
  constructor(shapeDir, options = {}) {
    this.shapeDir = shapeDir;
    this.dataDate = options.dataDate || DEFAULT_DATA_DATE;
    this.attribution = options.attribution || ATTRIBUTION;
    this.loaded = null;
    this.error = null;
  }

  reload() {
    this.error = null;
    this.loaded = null;
    const missing = [];
    let network;
    let seq;
    try {
      network = loadTable(this.shapeDir, 'ROUTE_NETWORK');
      seq = loadTable(this.shapeDir, 'BUS_ROUTE_SEQ');
    } catch (err) {
      this.error = { success: false, points: [], error: 'shapefile_read_failed', detail: err.message };
      return this;
    }
    if (!network) missing.push('ROUTE_NETWORK.shp/.dbf');
    if (!seq) missing.push('BUS_ROUTE_SEQ.dbf');
    if (missing.length) {
      this.error = { success: false, points: [], error: 'shapefile_missing', missing };
      return this;
    }
    if (!network.shp) {
      this.error = { success: false, points: [], error: 'shapefile_missing', missing: ['ROUTE_NETWORK.shp'] };
      return this;
    }
    const fields = {
      route: pickField(seq.fieldNames, ROUTE_FIELDS),
      networkId: pickField(seq.fieldNames, NETWORK_ID_FIELDS),
      seq: pickField(seq.fieldNames, SEQ_FIELDS),
      dir: pickField(seq.fieldNames, DIR_FIELDS),
      networkKey: pickField(network.fieldNames, NETWORK_ID_FIELDS),
    };
    if (!fields.route || !fields.networkId) {
      this.error = {
        success: false,
        points: [],
        error: 'unexpected_fields',
        seqFields: seq.fieldNames,
        networkFields: network.fieldNames,
      };
      return this;
    }
    this.loaded = {
      network,
      seq,
      fields,
      networkIndex: indexNetwork(network),
    };
    return this;
  }

  ensure() {
    if (!this.loaded && !this.error) this.reload();
    return this;
  }

  shape(route, dir) {
    this.ensure();
    const requested = upper(route);
    const direction = Number(dir) || 0;
    if (this.error) return { ...this.error, route: requested, dir: direction, attribution: this.attribution, dataDate: this.dataDate };
    const assembled = this._assemble(requested, direction);
    if (!assembled.success && assembled.error === 'no_shape') {
      const express = requested.match(/^(\d+)X$/);
      if (express) {
        const fallback = this._assemble(express[1], direction);
        if (fallback.success) {
          return this._envelope(requested, direction, { ...fallback, matchedRoute: express[1] });
        }
      }
    }
    return this._envelope(requested, direction, assembled);
  }

  _assemble(route, dir) {
    return assembleRoute(
      this.loaded.seq.rows,
      this.loaded.networkIndex,
      route,
      dir,
      this.loaded.fields,
    );
  }

  _envelope(route, dir, assembled) {
    return {
      route,
      dir,
      source: 'ROUTE_NETWORK',
      attribution: this.attribution,
      dataDate: this.dataDate,
      ...assembled,
    };
  }

  inspect() {
    this.ensure();
    if (this.error) return this.error;
    const { network, seq, fields } = this.loaded;
    const routes = [];
    const seen = new Set();
    for (const row of seq.rows) {
      if (row.deleted) continue;
      const code = upper(fieldValue(row, fields.route));
      if (!code || seen.has(code)) continue;
      seen.add(code);
      if (routes.length < 12) routes.push(code);
    }
    return {
      shapeDir: this.shapeDir,
      attribution: this.attribution,
      dataDate: this.dataDate,
      networkFields: network.fieldNames,
      seqFields: seq.fieldNames,
      detected: fields,
      networkFeatures: network.rows.length,
      seqRows: seq.rows.length,
      sampleRoutes: routes,
      prj: network.prj ? network.prj.slice(0, 180) : '',
    };
  }
}

function sendJson(res, status, body) {
  const text = JSON.stringify(body);
  if (typeof res.status === 'function' && typeof res.json === 'function') {
    res.status(status).json(body);
    return;
  }
  res.statusCode = status;
  if (typeof res.setHeader === 'function') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  res.end(text);
}

function statusFor(body) {
  if (body.success) return 200;
  if (body.error === 'shapefile_missing' || body.error === 'shapefile_read_failed' || body.error === 'unexpected_fields') {
    return 503;
  }
  return 404;
}

function createHandler(index) {
  return function routeShapeHandler(req, res) {
    const query = (req.query && typeof req.query === 'object') ? req.query : {};
    let route = query.route;
    let dir = query.dir;
    if (route == null && req.url) {
      const url = new URL(req.url, 'http://localhost');
      route = url.searchParams.get('route');
      dir = url.searchParams.get('dir');
    }
    const body = index.shape(route || '', dir || 0);
    sendJson(res, statusFor(body), body);
  };
}

function mountRouteShape(app, options = {}) {
  const shapeDir = options.shapeDir || process.env.SHAPE_DIR || process.cwd();
  const index = options.index || new RouteShapeIndex(shapeDir, options);
  index.ensure();
  const handler = createHandler(index);
  const paths = options.paths || ['/api/route-shape', '/route-shape'];
  for (const routePath of paths) {
    app.get(routePath, handler);
  }
  return { index, handler };
}

function mountDisabledBusGpx(app) {
  const handler = (req, res) => {
    sendJson(res, 410, {
      success: false,
      error: 'bus-gpx removed; use /api/route-shape (ROUTE_NETWORK)',
    });
  };
  for (const routePath of ['/api/bus-gpx', '/bus-gpx']) {
    app.get(routePath, handler);
  }
  return handler;
}

function parseArgs(argv) {
  const out = { shapeDir: process.cwd(), route: '', dir: 0, inspect: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--inspect') out.inspect = true;
    else if (arg === '--shape-dir') out.shapeDir = argv[++i];
    else if (arg === '--route') out.route = argv[++i];
    else if (arg === '--route-dir') out.dir = Number(argv[++i] || 0);
  }
  return out;
}

if (require.main === module) {
  const args = parseArgs(process.argv.slice(2));
  const index = new RouteShapeIndex(args.shapeDir);
  if (args.inspect || !args.route) {
    console.log(JSON.stringify(index.inspect(), null, 2));
  }
  if (args.route) {
    console.log(JSON.stringify(index.shape(args.route, args.dir), null, 2));
  }
}

module.exports = {
  ATTRIBUTION,
  DEFAULT_DATA_DATE,
  MACAU_GRID,
  MACAU_LAT_OFFSET,
  MACAU_LNG_OFFSET,
  toLatLngPoints,
  splitDiscontinuous,
  chainRings,
  RouteShapeIndex,
  assembleRoute,
  readDbf,
  readShpRings,
  mountRouteShape,
  mountDisabledBusGpx,
  createHandler,
  routeMatches,
  normId,
};
