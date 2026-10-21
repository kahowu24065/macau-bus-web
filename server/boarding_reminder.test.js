'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http2 = require('http2');
const {
  estimateArrivalSeconds,
  planReminder,
  buildLiveActivityPayload,
  createBoardingReminders,
  minutesText,
  segmentsFromLearnedEta,
} = require('./boarding_reminder');

const LAT_METERS = 110540;
const baseLat = 22.19;
const lng = 113.54;

function north(meters) {
  return baseLat + meters / LAT_METERS;
}

function stop(seq, meters) {
  return { seq, lat: north(meters), lng };
}

const partialSegments = [
  { fromSeq: 1, toSeq: 2, travelSeconds: 100, dwellSeconds: 20 },
  { fromSeq: 2, toSeq: 3, travelSeconds: 200, dwellSeconds: 40 },
];

test('partial segment adds intermediate dwell and later travel, not dwell at the target', () => {
  const result = estimateArrivalSeconds({
    lat: north(250),
    lng,
    targetSeq: 3,
    stops: [stop(1, 0), stop(2, 500), stop(3, 1000)],
    segments: partialSegments,
  });
  assert.equal(result.ok, true);
  assert.equal(result.passed, false);
  assert.ok(Math.abs(result.remainingSeconds - 270) < 1);
  assert.notEqual(Math.round(result.remainingSeconds), 270 + 40);
});

test('a point past the target is already passed', () => {
  const result = estimateArrivalSeconds({
    lat: north(1200),
    lng,
    targetSeq: 3,
    stops: [stop(1, 0), stop(2, 500), stop(3, 1000)],
    segments: partialSegments,
  });
  assert.equal(result.passed, true);
  assert.ok(result.remainingSeconds <= 0);
});

test('the estimator does not open a network connection', () => {
  const original = http2.connect;
  let calls = 0;
  http2.connect = () => {
    calls += 1;
    throw new Error('network');
  };
  try {
    const result = estimateArrivalSeconds({
      lat: north(250),
      lng,
      targetSeq: 3,
      stops: [stop(1, 0), stop(2, 500), stop(3, 1000)],
      segments: partialSegments,
    });
    assert.ok(Math.abs(result.remainingSeconds - 270) < 1);
    assert.equal(calls, 0);
  } finally {
    http2.connect = original;
  }
});

test('push content is predicted minutes and does not include a stop count', () => {
  const payload = buildLiveActivityPayload({
    event: 'update',
    minutes: 5,
    text: minutesText('en', 5),
    route: '3A',
    stopName: 'Border Gate',
    lang: 'en',
    nowSeconds: 1_700_000_000,
  });
  const state = payload.aps['content-state'];
  assert.deepEqual(Object.keys(state).sort(), ['etaLabel', 'minutes', 'text']);
  assert.equal(state.etaLabel, 'Predicted arrival in');
  assert.equal(state.minutes, 5);
  assert.equal(state.text, 'Predicted arrival in 5 minutes');
  const encoded = JSON.stringify(payload);
  assert.doesNotMatch(encoded, /stopsAway|stopCount|stopsLeft|paragens|站數/);
  assert.doesNotMatch(state.text, /\d+\s+stops/);
});

test('the countdown names the stop in every language', () => {
  assert.equal(minutesText('zh', 3, '關閘'), '預測到站時間尚餘 3 分鐘 · 關閘');
  assert.equal(minutesText('zhHans', 3, '关闸'), '预测到站时间尚余 3 分钟 · 关闸');
  assert.equal(minutesText('en', 3, 'Border Gate'), 'Predicted arrival in 3 minutes · Border Gate');
  assert.equal(minutesText('en', 1, 'Border Gate'), 'Predicted arrival in 1 minute · Border Gate');
  assert.equal(minutesText('pt', 3, 'Portas do Cerco'), 'Chegada prevista em 3 minutos · Portas do Cerco');
  assert.equal(minutesText('pt', 1, 'Portas do Cerco'), 'Chegada prevista em 1 minuto · Portas do Cerco');
  assert.equal(minutesText('zh', 3, ''), '預測到站時間尚餘 3 分鐘');
});

test('a remote start puts the predicted-arrival label on the activity and the banner', () => {
  const payload = buildLiveActivityPayload({
    event: 'start',
    minutes: 3,
    text: minutesText('zh', 3, '關閘'),
    route: '3A',
    stopName: '關閘',
    lang: 'zh',
    nowSeconds: 1_700_000_000,
  });
  assert.equal(payload.aps.attributes.etaLabel, '預測到站時間尚餘');
  assert.equal(payload.aps['content-state'].etaLabel, '預測到站時間尚餘');
  assert.equal(payload.aps.alert.title, '3A');
  assert.equal(payload.aps.alert.body, '預測到站時間尚餘 3 分鐘 · 關閘');
  assert.equal(
    buildLiveActivityPayload({
      event: 'start',
      minutes: 1,
      text: minutesText('en', 1, 'Border Gate'),
      route: '3A',
      stopName: 'Border Gate',
      lang: 'en',
      nowSeconds: 1_700_000_000,
    }).aps.attributes.etaLabel,
    'Predicted arrival in',
  );
});

test('updates every 20 seconds from the original estimate, then ends at the stop', async () => {
  const pushes = [];
  const timers = [];
  let clock = 1_000_000;
  const book = createBoardingReminders({
    now: () => clock,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 480, dwellSeconds: 30 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      const id = timers.length + 1;
      timers.push({ id, ms, fn });
      return id;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      pushes.push(message);
      return { sent: true };
    },
  });

  const eight = await book.register({
    reminderId: 'eight',
    route: '3A',
    dir: 0,
    targetSeq: 2,
    stopName: 'Border Gate',
    lat: north(0),
    lng,
    lang: 'en',
    activityToken: 'activity-token',
    stops: [stop(1, 0), stop(2, 500)],
  });
  assert.equal(eight.body.success, true);
  assert.equal(eight.body.minutes, 8);
  assert.equal(eight.body.text, 'Predicted arrival in 8 minutes · Border Gate');
  assert.equal(eight.body.updateIntervalSeconds, 20);
  assert.equal(Math.round(eight.body.pushDelaySeconds), 20);
  assert.equal(Math.round(eight.body.endDelaySeconds), 480);
  assert.equal(pushes.length, 0);
  assert.equal(timers.length, 1);
  assert.equal(timers[0].ms, 20000);

  clock += 20000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].payload.aps.event, 'update');
  assert.equal(pushes[0].payload.aps['content-state'].minutes, 8);
  assert.ok(Number.isFinite(pushes[0].payload.aps['content-state'].endsAt));
  assert.equal(pushes[0].payload.aps['content-state'].etaLabel, 'Predicted arrival in');
  assert.equal(pushes[0].payload.aps['content-state'].text, 'Predicted arrival in 8 minutes · Border Gate');
  assert.equal(pushes[0].topic, 'mo.mbka.bus.push-type.liveactivity');
  assert.doesNotMatch(JSON.stringify(pushes[0].payload), /stopsAway|stopCount|stopsLeft|paragens/);

  clock += 80000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes[1].payload.aps.event, 'update');
  assert.equal(pushes[1].payload.aps['content-state'].minutes, 6);
  assert.equal(pushes[1].payload.aps['content-state'].text, 'Predicted arrival in 6 minutes · Border Gate');

  clock = 1_000_000 + 480000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes[2].payload.aps.event, 'end');
  assert.equal(pushes[2].payload.aps['content-state'].minutes, 0);
  assert.equal(pushes[2].payload.aps['content-state'].text, 'Arrived at Border Gate');
  assert.equal(book.reminders.has('eight'), false);
  assert.doesNotMatch(JSON.stringify(pushes[2].payload), /stopsAway|stopCount|stopsLeft/);
});

test('a token that arrives after a missed tick sends the current countdown', async () => {
  const pushes = [];
  const timers = [];
  let clock = 2_000_000;
  const book = createBoardingReminders({
    now: () => clock,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 200, dwellSeconds: 0 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      timers.push({ ms, fn });
      return timers.length;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      pushes.push(message);
      return { sent: true };
    },
  });
  const first = await book.register({
    reminderId: 'late',
    route: '3A',
    dir: 0,
    targetSeq: 2,
    stopName: '關閘',
    lat: north(0),
    lng,
    lang: 'zh',
    stops: [stop(1, 0), stop(2, 500)],
  });
  assert.equal(Math.round(first.body.pushDelaySeconds), 20);
  assert.equal(pushes.length, 0);
  assert.equal(book.reminders.get('late').activityToken, '');

  clock += 20000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes.length, 0);
  assert.equal(book.reminders.get('late').pendingTokenPush, true);

  const second = await book.register({ reminderId: 'late', activityToken: 'abc123hex' });
  assert.equal(second.status, 200);
  assert.equal(book.reminders.get('late').activityToken, 'abc123hex');
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].token, 'abc123hex');
  assert.equal(pushes[0].payload.aps.event, 'update');
  assert.equal(pushes[0].payload.aps['content-state'].minutes, 3);
  assert.equal(pushes[0].payload.aps['content-state'].etaLabel, '預測到站時間尚餘');
  assert.equal(pushes[0].payload.aps['content-state'].text, '預測到站時間尚餘 3 分鐘 · 關閘');
  assert.doesNotMatch(JSON.stringify(pushes[0].payload), /stopsAway|stopCount|stopsLeft/);
});

test('a token that arrives before the first 20 second tick does not send early', async () => {
  const pushes = [];
  const timers = [];
  let clock = 3_000_000;
  const book = createBoardingReminders({
    now: () => clock,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 480, dwellSeconds: 0 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      timers.push({ ms, fn });
      return timers.length;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      pushes.push(message);
      return { sent: true };
    },
  });
  await book.register({
    reminderId: 'wait',
    route: '3A',
    dir: 0,
    targetSeq: 2,
    stopName: 'Border Gate',
    lat: north(0),
    lng,
    lang: 'en',
    stops: [stop(1, 0), stop(2, 500)],
  });
  await book.register({ reminderId: 'wait', activityToken: 'later-token' });
  assert.equal(pushes.length, 0);
  clock += 20000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].token, 'later-token');
  assert.equal(pushes[0].payload.aps['content-state'].minutes, 8);
  assert.equal(pushes[0].payload.aps['content-state'].text, 'Predicted arrival in 8 minutes · Border Gate');
});

test('the same reminder id does not schedule a second time', async () => {
  let timers = 0;
  const book = createBoardingReminders({
    now: () => 3_000_000,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 480, dwellSeconds: 0 }],
    credentials: () => ({ configured: false }),
    setTimer: () => {
      timers += 1;
      return timers;
    },
    clearTimer: () => {},
  });
  const body = {
    reminderId: 'same',
    route: '1',
    dir: 0,
    targetSeq: 2,
    lat: north(0),
    lng,
    lang: 'zh',
    stops: [stop(1, 0), stop(2, 400)],
  };
  const first = await book.register(body);
  const second = await book.register({ ...body, activityToken: 'later-token' });
  assert.equal(first.body.reminderId, 'same');
  assert.equal(second.body.reminderId, 'same');
  assert.equal(timers, 1);
  assert.equal(book.reminders.get('same').activityToken, 'later-token');
});

test('missing segment times are refused and do not call APNs', async () => {
  const original = http2.connect;
  let calls = 0;
  http2.connect = () => {
    calls += 1;
    throw new Error('network');
  };
  try {
    const book = createBoardingReminders({
      now: () => 4_000_000,
      loadSegments: () => null,
      credentials: () => ({ configured: false }),
      setTimer: () => {
        throw new Error('should not schedule');
      },
    });
    const result = await book.register({
      reminderId: 'missing',
      route: '3A',
      dir: 0,
      targetSeq: 2,
      lat: north(0),
      lng,
      stops: [stop(1, 0), stop(2, 400)],
    });
    assert.equal(result.status, 503);
    assert.equal(result.body.code, 'segment_times_missing');
    assert.equal(calls, 0);
  } finally {
    http2.connect = original;
  }
});

test('a passed bus does not schedule a push', async () => {
  let timers = 0;
  const book = createBoardingReminders({
    now: () => 5_000_000,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 100, dwellSeconds: 10 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus' }),
    setTimer: () => {
      timers += 1;
      return timers;
    },
    sendPush: async () => {
      throw new Error('should not push');
    },
  });
  const result = await book.register({
    reminderId: 'gone',
    route: '3A',
    dir: 0,
    targetSeq: 2,
    lat: north(800),
    lng,
    stops: [stop(1, 0), stop(2, 400)],
  });
  assert.equal(result.body.code, 'passed');
  assert.equal(timers, 0);
});

test('learned_eta hops become segment rows, including route 102', async () => {
  const learnedEta = {
    routeDirStopCount(route, dir) {
      if (route === '102' && dir === 0) return 4;
      return 0;
    },
    getSegmentSeconds(route, dir, fromSeq, stopCount) {
      if (route === '102' && dir === 0 && fromSeq === 1 && stopCount === 4) {
        return [100, 80, 40];
      }
      return null;
    },
  };
  const withGap = {
    routeDirStopCount: () => 4,
    getSegmentSeconds: () => [90, null, 40],
  };

  assert.deepEqual(segmentsFromLearnedEta(withGap, '102', 0), [
    { fromSeq: 1, toSeq: 2, travelSeconds: 90, dwellSeconds: 25 },
    { fromSeq: 3, toSeq: 4, travelSeconds: 40, dwellSeconds: 25 },
  ]);
  assert.equal(segmentsFromLearnedEta(learnedEta, '102', 'A')[0].fromSeq, 1);
  assert.equal(segmentsFromLearnedEta(learnedEta, '102', 'B'), null);
  assert.equal(segmentsFromLearnedEta(learnedEta, '3A', 0), null);
  assert.equal(segmentsFromLearnedEta({ routeDirStopCount: () => 1 }, '102', 0), null);

  const book = createBoardingReminders({
    now: () => 6_000_000,
    loadSegments: (route, dir) => segmentsFromLearnedEta(learnedEta, route, dir),
    credentials: () => ({ configured: false }),
    setTimer: () => 1,
    clearTimer: () => {},
  });
  const result = await book.register({
    reminderId: 'r102',
    route: '102',
    dir: 0,
    targetSeq: 4,
    lat: north(0),
    lng,
    lang: 'zh',
    stops: [stop(1, 0), stop(2, 400), stop(3, 800), stop(4, 1200)],
  });
  assert.equal(result.status, 200);
  assert.equal(result.body.success, true);
  assert.notEqual(result.body.code, 'segment_times_missing');
});

test('planReminder counts down every 20 seconds instead of waiting for five minutes', () => {
  const later = planReminder(8 * 60);
  assert.equal(later.updateIntervalSeconds, 20);
  assert.equal(later.nextDelaySeconds, 20);
  assert.equal(later.minutesNow, 8);
  assert.equal(later.endDelaySeconds, 8 * 60);
  const close = planReminder(200);
  assert.equal(close.nextDelaySeconds, 20);
  assert.equal(close.minutesNow, 3);
  const almost = planReminder(12);
  assert.equal(almost.nextDelaySeconds, 12);
  assert.equal(almost.minutesNow, 1);
});

test('cancel stops a later tick, and a new reminder replaces one with the same token', async () => {
  const pushes = [];
  const timers = [];
  let clock = 7_000_000;
  const book = createBoardingReminders({
    now: () => clock,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 300, dwellSeconds: 0 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      timers.push({ ms, fn });
      return timers.length;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      pushes.push(message);
      return { sent: true };
    },
  });
  const body = {
    route: '3A',
    dir: 0,
    targetSeq: 2,
    stopName: 'Border Gate',
    lat: north(0),
    lng,
    lang: 'en',
    activityToken: 'phone-token',
    stops: [stop(1, 0), stop(2, 500)],
  };
  await book.register({ ...body, reminderId: 'old' });
  assert.equal(book.cancel('old').success, true);
  clock += 20000;
  await timers[0].fn();
  assert.equal(pushes.length, 0);
  assert.equal(book.reminders.has('old'), false);

  await book.register({ ...body, reminderId: 'first' });
  const firstTimer = timers[timers.length - 1];
  await book.register({ ...body, reminderId: 'second', stopName: 'Ferry' });
  assert.equal(book.reminders.has('first'), false);
  assert.equal(book.reminders.has('second'), true);
  clock += 20000;
  await firstTimer.fn();
  assert.equal(pushes.length, 0);
  await timers[timers.length - 1].fn();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].token, 'phone-token');
  assert.equal(pushes[0].payload.aps['content-state'].text, 'Predicted arrival in 5 minutes · Ferry');
});

test('realtimeEndsAt replaces the learned countdown for pushes', async () => {
  const pushes = [];
  const timers = [];
  let clock = 4_000_000;
  const book = createBoardingReminders({
    now: () => clock,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 14 * 60, dwellSeconds: 0 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      timers.push({ ms, fn });
      return timers.length;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      pushes.push(message);
      return { sent: true };
    },
  });

  const realtimeEndsAt = Math.floor(clock / 1000) + 9 * 60;
  const registered = await book.register({
    reminderId: 'live',
    route: '102',
    dir: 0,
    targetSeq: 2,
    stopName: '漁翁街',
    lat: north(0),
    lng,
    lang: 'zh',
    activityToken: 'activity-token',
    realtimeEndsAt,
    stops: [stop(1, 0), stop(2, 500)],
  });
  assert.equal(registered.body.success, true);
  assert.equal(registered.body.minutes, 9);
  assert.equal(Math.round(registered.body.endDelaySeconds), 9 * 60);
  assert.equal(pushes.length, 0);

  clock += 20000;
  await timers[timers.length - 1].fn();
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].payload.aps.event, 'update');
  assert.equal(pushes[0].payload.aps['content-state'].minutes, 9);
  assert.equal(pushes[0].payload.aps['content-state'].endsAt, realtimeEndsAt);
  assert.equal(pushes[0].payload.aps['content-state'].etaLabel, '預測到站時間尚餘');

  const moved = Math.floor(clock / 1000) + 6 * 60;
  const follow = await book.register({
    reminderId: 'live',
    realtimeEndsAt: moved,
  });
  assert.equal(follow.body.minutes, 6);
  assert.equal(pushes.length, 2);
  assert.equal(pushes[1].payload.aps.event, 'update');
  assert.equal(pushes[1].payload.aps['content-state'].minutes, 6);
  assert.equal(pushes[1].payload.aps['content-state'].endsAt, moved);

  const arrived = await book.register({
    reminderId: 'live',
    realtimeEndsAt: Math.floor(clock / 1000),
  });
  assert.equal(arrived.body.success, true);
  assert.equal(book.reminders.has('live'), true);
  assert.equal(pushes.length, 2);
  assert.notEqual(pushes[pushes.length - 1].payload.aps.event, 'end');
});
