'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const proj4 = require('proj4');
const {
  MACAU_GRID,
  MACAU_LAT_OFFSET,
  MACAU_LNG_OFFSET,
  RouteShapeIndex,
  mountDisabledBusGpx,
  readDbf,
  readShpRings,
  routeMatches,
  toLatLngPoints,
} = require('./route_shape');

function writeDbf(file, fieldDefs, rows) {
  const headerLen = 32 + fieldDefs.length * 32 + 1;
  const recordLen = 1 + fieldDefs.reduce((sum, field) => sum + field.size, 0);
  const buf = Buffer.alloc(headerLen + rows.length * recordLen + 1);
  buf.writeUInt8(0x03, 0);
  const now = new Date();
  buf.writeUInt8(now.getFullYear() - 1900, 1);
  buf.writeUInt8(now.getMonth() + 1, 2);
  buf.writeUInt8(now.getDate(), 3);
  buf.writeUInt32LE(rows.length, 4);
  buf.writeUInt16LE(headerLen, 8);
  buf.writeUInt16LE(recordLen, 10);
  fieldDefs.forEach((field, i) => {
    const off = 32 + i * 32;
    buf.write(field.name, off, 'ascii');
    buf.write(field.type, off + 11, 'ascii');
    buf.writeUInt8(field.size, off + 16);
    buf.writeUInt8(field.dec || 0, off + 17);
  });
  buf.writeUInt8(0x0d, headerLen - 1);
  rows.forEach((row, ri) => {
    let cursor = headerLen + ri * recordLen;
    buf.writeUInt8(0x20, cursor);
    cursor += 1;
    for (const field of fieldDefs) {
      if (field.type === 'N') {
        const text = Number(row[field.name]).toFixed(field.dec || 0).padStart(field.size, ' ').slice(0, field.size);
        buf.write(text, cursor, 'ascii');
      } else {
        const text = String(row[field.name] ?? '').padEnd(field.size, ' ').slice(0, field.size);
        buf.write(text, cursor, 'ascii');
      }
      cursor += field.size;
    }
  });
  buf.writeUInt8(0x1a, headerLen + rows.length * recordLen);
  fs.writeFileSync(file, buf);
}

function writePolylineShp(file, records) {
  const contents = records.map((ring) => {
    let xmin = Infinity;
    let ymin = Infinity;
    let xmax = -Infinity;
    let ymax = -Infinity;
    for (const [x, y] of ring) {
      xmin = Math.min(xmin, x);
      ymin = Math.min(ymin, y);
      xmax = Math.max(xmax, x);
      ymax = Math.max(ymax, y);
    }
    const contentBytes = 4 + 32 + 4 + 4 + 4 + ring.length * 16;
    const body = Buffer.alloc(contentBytes);
    body.writeInt32LE(3, 0);
    body.writeDoubleLE(xmin, 4);
    body.writeDoubleLE(ymin, 12);
    body.writeDoubleLE(xmax, 20);
    body.writeDoubleLE(ymax, 28);
    body.writeInt32LE(1, 36);
    body.writeInt32LE(ring.length, 40);
    body.writeInt32LE(0, 44);
    ring.forEach(([x, y], i) => {
      body.writeDoubleLE(x, 48 + i * 16);
      body.writeDoubleLE(y, 56 + i * 16);
    });
    return body;
  });
  const words = contents.reduce((sum, body) => sum + 4 + body.length / 2, 50);
  const fileBuf = Buffer.alloc(100 + contents.reduce((sum, body) => sum + 8 + body.length, 0));
  fileBuf.writeInt32BE(9994, 0);
  fileBuf.writeInt32BE(words, 24);
  fileBuf.writeInt32LE(1000, 28);
  fileBuf.writeInt32LE(3, 32);
  let offset = 100;
  contents.forEach((body, i) => {
    fileBuf.writeInt32BE(i + 1, offset);
    fileBuf.writeInt32BE(body.length / 2, offset + 4);
    body.copy(fileBuf, offset + 8);
    offset += 8 + body.length;
  });
  fs.writeFileSync(file, fileBuf);
}

function fixtureDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'route-shape-'));
  writePolylineShp(path.join(dir, 'ROUTE_NETWORK.shp'), [
    [[113.54, 22.19], [113.55, 22.20]],
    [[113.56, 22.21], [113.55, 22.20]],
  ]);
  writeDbf(path.join(dir, 'ROUTE_NETWORK.dbf'), [
    { name: 'NETWORK_ID', type: 'N', size: 8, dec: 0 },
  ], [
    { NETWORK_ID: 10 },
    { NETWORK_ID: 11 },
  ]);
  writeDbf(path.join(dir, 'BUS_ROUTE_SEQ.dbf'), [
    { name: 'ROUTE_NOS', type: 'C', size: 12, dec: 0 },
    { name: 'NETWORK_ID', type: 'N', size: 8, dec: 0 },
    { name: 'SEQ', type: 'N', size: 4, dec: 0 },
    { name: 'DIR', type: 'N', size: 2, dec: 0 },
  ], [
    { ROUTE_NOS: '1A', NETWORK_ID: 10, SEQ: 1, DIR: 0 },
    { ROUTE_NOS: '1A', NETWORK_ID: 11, SEQ: 2, DIR: 0 },
    { ROUTE_NOS: '1A,3X', NETWORK_ID: 11, SEQ: 1, DIR: 1 },
    { ROUTE_NOS: '1A,3X', NETWORK_ID: 10, SEQ: 2, DIR: 1 },
    { ROUTE_NOS: '52', NETWORK_ID: 10, SEQ: 1, DIR: 0 },
  ]);
  fs.writeFileSync(path.join(dir, 'BUS_POLE.dbf'), 'unused');
  return dir;
}

test('Macau Grid meters become WGS84 with the BUS_POLE offsets', () => {
  const sample = [[19956, 19416], [20000, 20000]];
  const out = toLatLngPoints(sample);
  assert.strictEqual(out.projected, true);
  assert.strictEqual(out.error, undefined);
  sample.forEach(([px, py], i) => {
    const [lng, lat] = proj4(MACAU_GRID, proj4.WGS84, [px, py]);
    assert.ok(Math.abs(out.points[i].lat - (lat + MACAU_LAT_OFFSET)) < 1e-12);
    assert.ok(Math.abs(out.points[i].lng - (lng + MACAU_LNG_OFFSET)) < 1e-12);
    assert.ok(out.points[i].lat > 22.05 && out.points[i].lat < 22.25);
    assert.ok(out.points[i].lng > 113.5 && out.points[i].lng < 113.6);
  });
  const geographic = toLatLngPoints([[113.54, 22.19]]);
  assert.strictEqual(geographic.projected, undefined);
  assert.deepStrictEqual(geographic.points, [{ lat: 22.19, lng: 113.54 }]);
});

test('route codes split on combined ROUTE_NOS', () => {
  assert.strictEqual(routeMatches('1A,3X', '3x'), true);
  assert.strictEqual(routeMatches('1A', '3'), false);
});

test('shapefile join follows NETWORK_ID order and flips a reversed edge', () => {
  const dir = fixtureDir();
  const dbf = readDbf(path.join(dir, 'ROUTE_NETWORK.dbf'));
  assert.deepStrictEqual(dbf.fields, ['NETWORK_ID']);
  const rings = readShpRings(path.join(dir, 'ROUTE_NETWORK.shp'));
  assert.strictEqual(rings.length, 2);

  const index = new RouteShapeIndex(dir, { dataDate: '2026-09-25' });
  const forward = index.shape('1A', 0);
  assert.strictEqual(forward.success, true);
  assert.strictEqual(forward.source, 'ROUTE_NETWORK');
  assert.strictEqual(forward.attribution, '澳門特別行政區政府數據開放平台');
  assert.strictEqual(forward.dataDate, '2026-09-25');
  assert.deepStrictEqual(forward.points, [
    { lat: 22.19, lng: 113.54 },
    { lat: 22.20, lng: 113.55 },
    { lat: 22.21, lng: 113.56 },
  ]);

  const back = index.shape('1a', 1);
  assert.deepStrictEqual(back.points, [
    { lat: 22.21, lng: 113.56 },
    { lat: 22.20, lng: 113.55 },
    { lat: 22.19, lng: 113.54 },
  ]);

  const shared = index.shape('3X', 1);
  assert.strictEqual(shared.success, true);
  const circular = index.shape('52', 1);
  assert.strictEqual(circular.success, true);
  assert.deepStrictEqual(circular.points, index.shape('52', 0).points);
  assert.strictEqual(index.shape('99Z', 0).error, 'no_shape');
});

test('bus-gpx is disabled and route-shape is served from the shapefile', async () => {
  const dir = fixtureDir();
  const routes = new Map();
  const app = {
    get(routePath, handler) {
      routes.set(routePath, handler);
    },
  };
  const { mountRouteShape } = require('./route_shape');
  mountRouteShape(app, { shapeDir: dir });
  mountDisabledBusGpx(app);

  const shape = await new Promise((resolve) => {
    routes.get('/api/route-shape')(
      { query: { route: '1A', dir: '0' } },
      { status(code) { this.code = code; return this; }, json(body) { resolve({ code: this.code, body }); } },
    );
  });
  assert.strictEqual(shape.code, 200);
  assert.strictEqual(shape.body.points.length, 3);

  const gone = await new Promise((resolve) => {
    routes.get('/api/bus-gpx')(
      { query: {} },
      { status(code) { this.code = code; return this; }, json(body) { resolve({ code: this.code, body }); } },
    );
  });
  assert.strictEqual(gone.code, 410);
  assert.match(gone.body.error, /route-shape/);
});

test('missing shapefiles are reported and not invented', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'route-shape-empty-'));
  const index = new RouteShapeIndex(dir);
  const body = index.shape('1A', 0);
  assert.strictEqual(body.success, false);
  assert.ok(body.missing.includes('ROUTE_NETWORK.shp/.dbf'));
  assert.ok(body.missing.includes('BUS_ROUTE_SEQ.dbf'));
});
