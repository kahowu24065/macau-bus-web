'use strict';

/**
 * Boarding reminder: one bus, one estimate, then a Live Activity countdown.
 *
 * The phone chooses the nearest bus traveling toward the stop and sends that
 * bus's coordinates once. This module estimates the rest of the trip from
 * those coordinates and the per-segment average travel times already on the
 * host. Travel time includes traffic lights and congestion. Dwell at a stop
 * is separate and is not added at the target stop.
 *
 * It does not call motransportinfo or any other transport-bureau URL.
 * The live host passes loadSegments from learned_eta (see segmentsFromLearnedEta).
 * segment_times.json is only the fallback when that callback is omitted.
 * If neither source has the route, the reminder is refused with segment_times_missing.
 *
 * Drop-in for the Oracle host (~/macau-bus/server.js), same pattern as
 * route_shape.js. The app process must stay up: the 20-second countdown
 * timer is in memory.
 *
 *   mountBoardingReminder(app, {
 *     shapeDir: __dirname,
 *     loadSegments: (route, dir) => segmentsFromLearnedEta(learnedEta, route, dir),
 *   });
 * segmentsFromLearnedEta is the learned_eta mapping inlined in ~/macau-bus/server.js.
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

const UPDATE_INTERVAL_SECONDS = 20;
const PASSED_METERS = 35;
const LAT_METERS = 110540;
const LNG_METERS = 111320 * Math.cos((22.2 * Math.PI) / 180);
const BUNDLE_ID = 'mo.mbka.bus';

function boardLog(msg, extra) {
  try {
    if (extra !== undefined) console.log(`[boarding] ${msg}`, extra);
    else console.log(`[boarding] ${msg}`);
  } catch (_) {}
}

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
  const nextDelaySeconds = Math.min(UPDATE_INTERVAL_SECONDS, remainingSeconds);
  return {
    passed: false,
    updateIntervalSeconds: UPDATE_INTERVAL_SECONDS,
    nextDelaySeconds,
    endDelaySeconds: remainingSeconds,
    minutesNow,
  };
}

function stopSuffix(stopName) {
  return stopName ? String(stopName).trim() : '';
}

function arrivalLabel(lang) {
  if (lang === 'zhHans') return '预测到站时间尚余';
  if (lang === 'en') return 'Predicted arrival in';
  if (lang === 'pt') return 'Chegada prevista em';
  return '預測到站時間尚餘';
}

function minutesText(lang, minutes, stopName) {
  const n = String(minutes);
  const stop = stopSuffix(stopName);
  const place = stop ? ` · ${stop}` : '';
  const label = arrivalLabel(lang);
  if (lang === 'en') {
    const unit = minutes === 1 ? 'minute' : 'minutes';
    return `${label} ${n} ${unit}${place}`;
  }
  if (lang === 'pt') {
    const unit = minutes === 1 ? 'minuto' : 'minutos';
    return `${label} ${n} ${unit}${place}`;
  }
  const unit = lang === 'zhHans' ? '分钟' : '分鐘';
  return `${label} ${n} ${unit}${place}`;
}

function arrivedText(lang, stopName) {
  const stop = stopSuffix(stopName);
  if (lang === 'zhHans') return stop ? `已到达${stop}` : '已到达';
  if (lang === 'en') return stop ? `Arrived at ${stop}` : 'Arrived';
  if (lang === 'pt') return stop ? `Chegou a ${stop}` : 'Chegou';
  return stop ? `已到達${stop}` : '已到達';
}

/**
 * Live Activity payload. content-state is predicted minutes and a sentence
 * that labels them as the predicted arrival time. It never includes a stop count.
 */
function buildLiveActivityPayload({ event, minutes, text, route, stopName, nowSeconds, endsAt, lang }) {
  const contentState = { minutes, text };
  if (Number.isFinite(endsAt) && endsAt > 0) contentState.endsAt = endsAt;
  const aps = {
    timestamp: nowSeconds,
    event,
    'content-state': contentState,
  };
  if (event === 'start') {
    aps['attributes-type'] = 'BoardingActivityAttributes';
    aps.attributes = {
      route: route || '',
      stopName: stopName || '',
      etaLabel: arrivalLabel(lang),
    };
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

/**
 * Segment rows from the host's learned_eta object.
 * Dir A/a is 0 and B/b is 1; a numeric dir is left as-is.
 * A missing hop is skipped. Dwell is the fixed 25s the live server uses.
 * Returns null when learned_eta has no usable chain for this route.
 */
function segmentsFromLearnedEta(learnedEta, route, dir) {
  const d = (dir === 'A' || dir === 'a') ? 0 : (dir === 'B' || dir === 'b') ? 1 : dir;
  const stopCount = learnedEta && typeof learnedEta.routeDirStopCount === 'function'
    ? learnedEta.routeDirStopCount(route, d) : 0;
  if (stopCount < 2) return null;
  const hops = learnedEta.getSegmentSeconds(route, d, 1, stopCount);
  if (!hops) return null;
  const segs = [];
  for (let i = 0; i < hops.length; i += 1) {
    if (hops[i] == null) continue;
    segs.push({
      fromSeq: i + 1,
      toSeq: i + 2,
      travelSeconds: hops[i],
      dwellSeconds: 25,
    });
  }
  return segs.length ? segs : null;
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
      lang: reminder.lang,
      nowSeconds: Math.floor(now() / 1000),
      endsAt: Math.floor(now() / 1000) + Math.max(0, Math.round(remainingSeconds(reminder))),
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
    reminder.timerSerial = (reminder.timerSerial || 0) + 1;
    if (reminder.pushTimer) clearTimer(reminder.pushTimer);
    reminder.pushTimer = null;
  }

  function remainingSeconds(reminder) {
    const elapsed = Math.max(0, (now() - reminder.registeredAt) / 1000);
    return reminder.initialRemainingSeconds - elapsed;
  }

  function publicResponse(reminder) {
    const remaining = Math.max(0, Math.round(remainingSeconds(reminder)));
    return {
      success: true,
      reminderId: reminder.id,
      minutes: reminder.minutesNow,
      text: reminder.text,
      startedAt: reminder.startedAt,
      pushConfigured: credentials().configured,
      updateIntervalSeconds: UPDATE_INTERVAL_SECONDS,
      pushDelaySeconds: Math.max(0, Math.round((reminder.nextDueAt - now()) / 1000)),
      endDelaySeconds: remaining,
      endsAt: Math.floor(now() / 1000) + remaining,
    };
  }

  function cancelOne(reminder) {
    if (!reminder || reminder.closed) return;
    reminder.closed = true;
    clearTimers(reminder);
    reminders.delete(reminder.id);
  }

  function cancelConflicts(reminder) {
    const activityToken = reminder.activityToken || '';
    const pushToStartToken = reminder.pushToStartToken || '';
    if (!activityToken && !pushToStartToken) return;
    for (const other of [...reminders.values()]) {
      if (other.id === reminder.id || other.closed) continue;
      const sameActivity = activityToken && other.activityToken === activityToken;
      const sameStart = pushToStartToken && other.pushToStartToken === pushToStartToken;
      if (!sameActivity && !sameStart) continue;
      cancelOne(other);
    }
  }

  function scheduleTick(reminder) {
    if (reminder.closed || !reminders.has(reminder.id)) return;
    clearTimers(reminder);
    const remaining = remainingSeconds(reminder);
    if (!(remaining > 0)) {
      reminder.nextDueAt = now();
      const serial = reminder.timerSerial;
      reminder.pushTimer = setTimer(() => {
        if (reminder.timerSerial !== serial || reminder.closed) return;
        return runTick(reminder);
      }, 0);
      return;
    }
    const delayMs = Math.round(Math.min(UPDATE_INTERVAL_SECONDS, remaining) * 1000);
    reminder.nextDueAt = now() + delayMs;
    const serial = reminder.timerSerial;
    reminder.pushTimer = setTimer(() => {
      if (reminder.timerSerial !== serial || reminder.closed) return;
      return runTick(reminder);
    }, delayMs);
  }

  async function finishReminder(reminder) {
    if (reminder.closed) return;
    const text = arrivedText(reminder.lang, reminder.stopName);
    cancelOne(reminder);
    await deliver(reminder, { event: 'end', minutes: 0, text });
  }

  async function runTick(reminder) {
    if (reminder.closed || !reminders.has(reminder.id) || reminder.ticking) return;
    reminder.ticking = true;
    try {
      const remaining = remainingSeconds(reminder);
      if (!(remaining > 0)) {
        await finishReminder(reminder);
        return;
      }
      const minutes = Math.max(1, Math.round(remaining / 60));
      reminder.minutesNow = minutes;
      reminder.text = minutesText(reminder.lang, minutes, reminder.stopName);
      if (!pushTarget(reminder)) {
        reminder.pendingTokenPush = true;
        boardLog('tick_no_token', { id: reminder.id, minutes, remaining: Math.round(remaining) });
        scheduleTick(reminder);
        return;
      }
      reminder.pendingTokenPush = false;
      const result = await deliver(reminder, {
        event: 'update',
        minutes,
        text: reminder.text,
      });
      if (result && result.sent) {
        reminder.pushDelivered = true;
        boardLog('tick_push_ok', { id: reminder.id, minutes });
      } else {
        boardLog('tick_push_fail', { id: reminder.id, minutes, reason: result && result.reason, status: result && result.status });
      }
      if (reminder.closed || !reminders.has(reminder.id)) return;
      scheduleTick(reminder);
    } finally {
      reminder.ticking = false;
    }
  }

  async function register(body) {
    const reminderId = body && body.reminderId ? String(body.reminderId) : '';
    if (!reminderId) return { status: 400, body: { success: false, code: 'bad_request' } };

    const existing = reminders.get(reminderId);
    if (existing && !existing.closed) {
      if (body.activityToken) existing.activityToken = String(body.activityToken);
      if (body.pushToStartToken) existing.pushToStartToken = String(body.pushToStartToken);
      cancelConflicts(existing);
      if (body.activityToken || body.pushToStartToken) {
        boardLog('token_attached', {
          id: reminderId,
          hasActivity: Boolean(existing.activityToken),
          hasPushToStart: Boolean(existing.pushToStartToken),
        });
      }
      // A tick that already came due had no token. Send the current countdown
      // now that the phone can receive it, instead of waiting out another 20s.
      if ((existing.pendingTokenPush || existing.nextDueAt <= now()) && pushTarget(existing)) {
        await runTick(existing);
      }
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
    const stopName = body.stopName ? String(body.stopName) : '';
    const reminder = {
      id: reminderId,
      route: body.route ? String(body.route) : '',
      stopName,
      lang,
      activityToken: body.activityToken ? String(body.activityToken) : '',
      pushToStartToken: body.pushToStartToken ? String(body.pushToStartToken) : '',
      startedAt,
      registeredAt: now(),
      initialRemainingSeconds: remaining,
      minutesNow: plan.minutesNow,
      text: minutesText(lang, plan.minutesNow, stopName),
      nextDueAt: now(),
      pendingTokenPush: false,
      pushDelivered: false,
      startedRemotely: false,
      closed: false,
      ticking: false,
      timerSerial: 0,
      pushTimer: null,
    };

    reminders.set(reminderId, reminder);
    cancelConflicts(reminder);
    boardLog('registered', {
      id: reminderId,
      minutes: reminder.minutesNow,
      remaining: Math.round(remaining),
      hasActivity: Boolean(reminder.activityToken),
      hasPushToStart: Boolean(reminder.pushToStartToken),
      pushConfigured: credentials().configured,
    });
    scheduleTick(reminder);
    return { status: 200, body: publicResponse(reminder) };
  }

  function cancel(reminderId) {
    const reminder = reminders.get(String(reminderId || ''));
    if (!reminder) return { success: true };
    cancelOne(reminder);
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
  UPDATE_INTERVAL_SECONDS,
  estimateArrivalSeconds,
  planReminder,
  minutesText,
  arrivedText,
  buildLiveActivityPayload,
  createBoardingReminders,
  mountBoardingReminder,
  loadSegmentTable,
  segmentsFromTable,
  segmentsFromLearnedEta,
  resolveSegmentPath,
  apnsJwt,
};
