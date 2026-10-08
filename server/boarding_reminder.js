'use strict';

/**
 * Boarding reminder: one bus, one estimate, one Apple Live Activity push.
 *
 * The phone chooses the nearest bus traveling toward the stop and sends that
 * bus's coordinates once. This module estimates the rest of the trip from
 * those coordinates and the per-segment average travel times already on the
 * host. Travel time includes traffic lights and congestion. Dwell at a stop
 * is separate and is not added at the target stop.
 *
 * It does not call motransportinfo or any other transport-bureau URL.
 * The segment averages are not in this git repo. Point SEGMENT_TIMES_PATH
 * (or shapeDir/segment_times.json) at the table the live server already uses.
 * If that file is missing, the reminder is refused with segment_times_missing.
 *
 * Drop-in for the Oracle host (~/macau-bus/server.js), same pattern as
 * route_shape.js. The app process must stay up: the five-minute and arrival
 * timers are in memory.
 *
 *   const { mountBoardingReminder } = require('./boarding_reminder');
 *   mountBoardingReminder(app, { shapeDir: '/home/ubuntu/macau-bus' });
 *
 * segment_times.json:
 *   { "3A": { "0": [ { "fromSeq": 1, "toSeq": 2, "travelSeconds": 90, "dwellSeconds": 20 } ] } }
 * dwellSeconds is the dwell at toSeq. It is not part of travelSeconds.
 *
 * Apple push needs APNS_KEY_ID, APNS_TEAM_ID, and APNS_KEY_P8 or APNS_KEY_PATH
 * (the .p8 for the existing developer account). APNS_BUNDLE_ID defaults to
 * mo.mbka.bus. APNS_USE_SANDBOX=1 selects api.sandbox.push.apple.com.
 * Nothing here invents a key. Without those values pushConfigured is false
 * and no push is sent.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const FIVE_MINUTES = 5 * 60;
const PASSED_METERS = 35;
const LAT_METERS = 110540;
const LNG_METERS = 111320 * Math.cos((22.2 * Math.PI) / 180);
const BUNDLE_ID = 'mo.mbka.bus';

function xy(lat, lng) {
  return { x: lng * LNG_METERS, y: lat * LAT_METERS };
}

function dist(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function usable(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) > 1 && Math.abs(lng) > 1;
}

function projectPoint(lat, lng, line) {
  const p = xy(lat, lng);
  let bestCross = Infinity;
  let bestAlong = 0;
  let bestIndex = 0;
  let bestT = 0;
  for (let i = 0; i < line.length - 1; i += 1) {
    const a = line[i];
    const b = line[i + 1];
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const len2 = abx * abx + aby * aby;
    let t = 0;
    if (len2 > 0) {
      t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2;
      if (t < 0) t = 0;
      else if (t > 1) t = 1;
    }
    const qx = a.x + abx * t;
    const qy = a.y + aby * t;
    const cross = Math.hypot(p.x - qx, p.y - qy);
    const along = a.along + Math.sqrt(len2) * t;
    if (cross < bestCross) {
      bestCross = cross;
      bestAlong = along;
      bestIndex = i;
      bestT = t;
    }
  }
  return { along: bestAlong, cross: bestCross, index: bestIndex, fraction: bestT };
}

function segmentKey(fromSeq, toSeq) {
  return `${fromSeq}->${toSeq}`;
}

function indexSegments(segments) {
  const map = new Map();
  for (const segment of segments || []) {
    const fromSeq = Number(segment.fromSeq);
    const toSeq = Number(segment.toSeq);
    const travelSeconds = Number(segment.travelSeconds);
    const dwellSeconds = Number(segment.dwellSeconds) || 0;
    if (!Number.isFinite(fromSeq) || !Number.isFinite(toSeq) || !Number.isFinite(travelSeconds)) {
      continue;
    }
    map.set(segmentKey(fromSeq, toSeq), { travelSeconds, dwellSeconds });
  }
  return map;
}

/**
 * Remaining seconds from one coordinate along the stop chain.
 * No network. Missing segment data returns segment_times_missing.
 * A point at or past the target returns passed.
 */
function estimateArrivalSeconds({ lat, lng, targetSeq, stops, segments }) {
  const ordered = (Array.isArray(stops) ? stops : [])
    .map((stop) => ({
      seq: Number(stop.seq),
      lat: Number(stop.lat),
      lng: Number(stop.lng),
    }))
    .filter((stop) => Number.isFinite(stop.seq) && usable(stop.lat, stop.lng))
    .sort((a, b) => a.seq - b.seq);

  if (ordered.length < 2) return { ok: false, code: 'segment_times_missing' };

  const targetIndex = ordered.findIndex((stop) => stop.seq === Number(targetSeq));
  if (targetIndex < 0) return { ok: false, code: 'bad_request' };

  const indexed = indexSegments(segments);
  if (indexed.size === 0) return { ok: false, code: 'segment_times_missing' };

  const line = [];
  let along = 0;
  for (let i = 0; i < ordered.length; i += 1) {
    const point = xy(ordered[i].lat, ordered[i].lng);
    if (i > 0) along += dist(xy(ordered[i - 1].lat, ordered[i - 1].lng), point);
    line.push({ x: point.x, y: point.y, along, seq: ordered[i].seq });
  }

  const busLat = Number(lat);
  const busLng = Number(lng);
  if (!usable(busLat, busLng)) return { ok: false, code: 'bad_request' };

  const projected = projectPoint(busLat, busLng, line);
  const targetAlong = line[targetIndex].along;
  if (projected.along >= targetAlong - PASSED_METERS) {
    return { ok: true, passed: true, remainingSeconds: 0 };
  }

  let index = projected.index;
  let fraction = projected.fraction;
  if (line[index].seq === Number(targetSeq) || index >= targetIndex) {
    return { ok: true, passed: true, remainingSeconds: 0 };
  }
  // The closest point can sit on an earlier vertex of a later segment.
  while (index < targetIndex - 1 && fraction >= 1) {
    index += 1;
    fraction = 0;
  }

  let seconds = 0;
  for (let i = index; i < targetIndex; i += 1) {
    const from = line[i];
    const to = line[i + 1];
    const segment = indexed.get(segmentKey(from.seq, to.seq));
    if (!segment) return { ok: false, code: 'segment_times_missing' };
    const span = i === index ? (1 - fraction) * segment.travelSeconds : segment.travelSeconds;
    seconds += span;
    const arrivesAtTarget = to.seq === Number(targetSeq);
    if (!arrivesAtTarget) seconds += segment.dwellSeconds;
  }

  return { ok: true, passed: false, remainingSeconds: Math.max(0, seconds) };
}

function planReminder(remainingSeconds) {
  if (!(remainingSeconds > 0)) return { passed: true };
  const minutesNow = Math.max(1, Math.round(remainingSeconds / 60));
  if (remainingSeconds <= FIVE_MINUTES) {
    return {
      passed: false,
      pushDelaySeconds: 0,
      pushMinutes: minutesNow,
      endDelaySeconds: remainingSeconds,
      minutesNow,
    };
  }
  return {
    passed: false,
    pushDelaySeconds: remainingSeconds - FIVE_MINUTES,
    pushMinutes: 5,
    endDelaySeconds: remainingSeconds,
    minutesNow,
  };
}

function minutesText(lang, minutes) {
  const n = String(minutes);
  if (lang === 'zhHans') return `约 ${n} 分钟后到达`;
  if (lang === 'en') {
    return minutes === 1 ? 'About 1 minute away' : `About ${n} minutes away`;
  }
  if (lang === 'pt') {
    return minutes === 1 ? 'A cerca de 1 minuto' : `A cerca de ${n} minutos`;
  }
  return `約 ${n} 分鐘後到達`;
}

function arrivedText(lang) {
  if (lang === 'zhHans') return '已到达';
  if (lang === 'en') return 'Arrived';
  if (lang === 'pt') return 'Chegou';
  return '已到達';
}

/**
 * Live Activity payload. content-state is predicted minutes and that sentence.
 * It never includes a stop count.
 */
function buildLiveActivityPayload({ event, minutes, text, route, stopName, nowSeconds }) {
  const contentState = { minutes, text };
  const aps = {
    timestamp: nowSeconds,
    event,
    'content-state': contentState,
  };
  if (event === 'start') {
    aps['attributes-type'] = 'BoardingActivityAttributes';
    aps.attributes = { route: route || '', stopName: stopName || '' };
    aps.alert = { title: route || '', body: text };
  } else if (event === 'update' || event === 'end') {
    aps.alert = { title: route || '', body: text };
  }
  if (event === 'end') aps['dismissal-date'] = nowSeconds;
  return { aps };
}

function defaultCredentials() {
  const keyId = process.env.APNS_KEY_ID || '';
  const teamId = process.env.APNS_TEAM_ID || '';
  let p8 = process.env.APNS_KEY_P8 || '';
  if (!p8 && process.env.APNS_KEY_PATH) {
    try {
      p8 = fs.readFileSync(process.env.APNS_KEY_PATH, 'utf8');
    } catch (_) {
      p8 = '';
    }
  }
  const configured = Boolean(keyId && teamId && p8);
  return {
    configured,
    keyId,
    teamId,
    p8,
    bundleId: process.env.APNS_BUNDLE_ID || BUNDLE_ID,
    sandbox: process.env.APNS_USE_SANDBOX === '1',
  };
}

function apnsJwt({ keyId, teamId, p8, nowSeconds }) {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId })).toString('base64url');
  const claims = Buffer.from(JSON.stringify({ iss: teamId, iat: nowSeconds })).toString('base64url');
  const data = `${header}.${claims}`;
  const sign = crypto.createSign('SHA256');
  sign.update(data);
  sign.end();
  const sig = sign.sign({ key: p8, dsaEncoding: 'ieee-p1363' });
  return `${data}.${sig.toString('base64url')}`;
}

function sendApns(deps, { token, topic, payload, sandbox }) {
  const http2 = deps.http2 || require('http2');
  const host = sandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
  const client = (deps.connect || http2.connect)(host);
  const jwt = apnsJwt({
    keyId: deps.credentials().keyId,
    teamId: deps.credentials().teamId,
    p8: deps.credentials().p8,
    nowSeconds: Math.floor(deps.now() / 1000),
  });
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      try { client.close(); } catch (_) { /* already closed */ }
      resolve(result);
    };
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      'apns-topic': topic,
      'apns-push-type': 'liveactivity',
      'apns-priority': '10',
    });
    req.setEncoding('utf8');
    let body = '';
    req.on('response', (headers) => {
      const status = Number(headers[':status'] || 0);
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => finish({ sent: status === 200, status, body }));
    });
    req.on('error', (error) => finish({ sent: false, error: String(error) }));
    req.end(JSON.stringify(payload));
  });
}

function loadSegmentTable(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (_) {
    return null;
  }
}

function segmentsFromTable(table, route, dir) {
  if (!table || !route) return null;
  const routeEntry = table[route] || table[String(route).toUpperCase()] || table[String(route).toLowerCase()];
  if (!routeEntry || typeof routeEntry !== 'object') return null;
  const dirEntry = routeEntry[String(dir)];
  return Array.isArray(dirEntry) ? dirEntry : null;
}

function resolveSegmentPath(options = {}) {
  if (options.segmentTimesPath) return options.segmentTimesPath;
  if (process.env.SEGMENT_TIMES_PATH) return process.env.SEGMENT_TIMES_PATH;
  const shapeDir = options.shapeDir || process.env.SHAPE_DIR || '/home/ubuntu/macau-bus';
  return path.join(shapeDir, 'segment_times.json');
}

function pushTarget(reminder) {
  if (reminder.activityToken) {
    return { token: reminder.activityToken, event: reminder.startedRemotely ? 'update' : 'update' };
  }
  if (reminder.pushToStartToken) {
    return { token: reminder.pushToStartToken, event: 'start' };
  }
  return null;
}

function createBoardingReminders(options = {}) {
  const reminders = new Map();
  const now = options.now || (() => Date.now());
  const setTimer = options.setTimer || ((fn, ms) => setTimeout(fn, ms));
  const clearTimer = options.clearTimer || ((id) => clearTimeout(id));
  const credentials = options.credentials || defaultCredentials;
  const tablePath = options.segmentTimesPath || (options.loadSegments ? null : resolveSegmentPath(options));
  let cachedTable;
  let cachedStamp = 0;

  function loadSegments(route, dir) {
    if (options.loadSegments) return options.loadSegments(route, dir);
    const stamp = now();
    if (!cachedTable || stamp - cachedStamp > 60 * 1000) {
      cachedTable = loadSegmentTable(tablePath);
      cachedStamp = stamp;
    }
    return segmentsFromTable(cachedTable, route, dir);
  }

  async function deliver(reminder, { event, minutes, text }) {
    const target = event === 'end' && reminder.activityToken
      ? { token: reminder.activityToken, event: 'end' }
      : (event === 'end' ? null : pushTarget(reminder));
    const creds = credentials();
    if (!creds.configured || !target) {
      return { sent: false, reason: !creds.configured ? 'push_not_configured' : 'no_token' };
    }
    const payload = buildLiveActivityPayload({
      event: event === 'end' ? 'end' : target.event,
      minutes,
      text,
      route: reminder.route,
      stopName: reminder.stopName,
      nowSeconds: Math.floor(now() / 1000),
    });
    if (target.event === 'start') reminder.startedRemotely = true;
    const message = {
      token: target.token,
      topic: `${creds.bundleId}.push-type.liveactivity`,
      payload,
      sandbox: creds.sandbox,
    };
    if (options.sendPush) return options.sendPush(message);
    return sendApns({ credentials, now, connect: options.connect, http2: options.http2 }, message);
  }

  function clearTimers(reminder) {
    if (reminder.pushTimer) clearTimer(reminder.pushTimer);
    if (reminder.endTimer) clearTimer(reminder.endTimer);
    reminder.pushTimer = null;
    reminder.endTimer = null;
  }

  function publicResponse(reminder) {
    return {
      success: true,
      reminderId: reminder.id,
      minutes: reminder.minutesNow,
      text: reminder.text,
      startedAt: reminder.startedAt,
      pushConfigured: credentials().configured,
      pushDelaySeconds: reminder.pushDelaySeconds,
      endDelaySeconds: reminder.endDelaySeconds,
    };
  }

  async function register(body) {
    const reminderId = body && body.reminderId ? String(body.reminderId) : '';
    if (!reminderId) return { status: 400, body: { success: false, code: 'bad_request' } };

    const existing = reminders.get(reminderId);
    if (existing) {
      if (body.activityToken) existing.activityToken = String(body.activityToken);
      if (body.pushToStartToken) existing.pushToStartToken = String(body.pushToStartToken);
      return { status: 200, body: publicResponse(existing) };
    }

    const segments = loadSegments(body.route, body.dir);
    if (!segments) {
      return { status: 503, body: { success: false, code: 'segment_times_missing' } };
    }

    const estimate = estimateArrivalSeconds({
      lat: body.lat,
      lng: body.lng,
      targetSeq: body.targetSeq,
      stops: body.stops,
      segments,
    });
    if (!estimate.ok) {
      const status = estimate.code === 'segment_times_missing' ? 503 : 400;
      return { status, body: { success: false, code: estimate.code } };
    }

    let remaining = estimate.remainingSeconds;
    const startedAt = Number(body.startedAt) || now();
    if (Number(body.startedAt)) {
      remaining -= Math.max(0, (now() - Number(body.startedAt)) / 1000);
    }
    if (estimate.passed || remaining <= 0) {
      return { status: 200, body: { success: false, code: 'passed' } };
    }

    const plan = planReminder(remaining);
    if (plan.passed) {
      return { status: 200, body: { success: false, code: 'passed' } };
    }

    const lang = body.lang || 'zh';
    const reminder = {
      id: reminderId,
      route: body.route ? String(body.route) : '',
      stopName: body.stopName ? String(body.stopName) : '',
      lang,
      activityToken: body.activityToken ? String(body.activityToken) : '',
      pushToStartToken: body.pushToStartToken ? String(body.pushToStartToken) : '',
      startedAt,
      minutesNow: plan.minutesNow,
      text: minutesText(lang, plan.minutesNow),
      pushDelaySeconds: plan.pushDelaySeconds,
      endDelaySeconds: plan.endDelaySeconds,
      startedRemotely: false,
      pushTimer: null,
      endTimer: null,
    };

    const sendUpdate = () => deliver(reminder, {
      event: 'update',
      minutes: plan.pushMinutes,
      text: minutesText(lang, plan.pushMinutes),
    });
    if (plan.pushDelaySeconds <= 0) {
      await sendUpdate();
    } else {
      reminder.pushTimer = setTimer(sendUpdate, Math.round(plan.pushDelaySeconds * 1000));
    }
    reminder.endTimer = setTimer(() => {
      return deliver(reminder, { event: 'end', minutes: 0, text: arrivedText(lang) })
        .finally(() => {
          clearTimers(reminder);
          reminders.delete(reminderId);
        });
    }, Math.round(plan.endDelaySeconds * 1000));

    reminders.set(reminderId, reminder);
    return { status: 200, body: publicResponse(reminder) };
  }

  function cancel(reminderId) {
    const reminder = reminders.get(String(reminderId || ''));
    if (!reminder) return { success: true };
    clearTimers(reminder);
    reminders.delete(reminder.id);
    return { success: true };
  }

  return { register, cancel, reminders, loadSegments };
}

function mountBoardingReminder(app, options = {}) {
  const book = options.book || createBoardingReminders(options);

  async function onRegister(req, res) {
    const result = await book.register(req.body || {});
    res.status(result.status).json(result.body);
  }

  function onCancel(req, res) {
    res.json(book.cancel((req.body || {}).reminderId));
  }

  app.post('/api/boarding-reminder', onRegister);
  app.post('/boarding-reminder', onRegister);
  app.post('/api/boarding-reminder/cancel', onCancel);
  app.post('/boarding-reminder/cancel', onCancel);
  return book;
}

module.exports = {
  PASSED_METERS,
  FIVE_MINUTES,
  estimateArrivalSeconds,
  planReminder,
  minutesText,
  arrivedText,
  buildLiveActivityPayload,
  createBoardingReminders,
  mountBoardingReminder,
  loadSegmentTable,
  segmentsFromTable,
  resolveSegmentPath,
  apnsJwt,
};
