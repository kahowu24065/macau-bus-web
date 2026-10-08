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
    nowSeconds: 1_700_000_000,
  });
  const state = payload.aps['content-state'];
  assert.deepEqual(Object.keys(state).sort(), ['minutes', 'text']);
  assert.equal(state.minutes, 5);
  assert.equal(state.text, 'About 5 minutes away');
  const encoded = JSON.stringify(payload);
  assert.doesNotMatch(encoded, /stopsAway|stopCount|stopsLeft|paragens|站數/);
  assert.doesNotMatch(state.text, /\d+\s+stops/);
});

test('about eight minutes pushes at three minutes; under five minutes pushes now', async () => {
  const pushes = [];
  const timers = [];
  const book = createBoardingReminders({
    now: () => 1_000_000,
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
  assert.equal(eight.body.text, 'About 8 minutes away');
  assert.equal(Math.round(eight.body.pushDelaySeconds), 180);
  assert.equal(Math.round(eight.body.endDelaySeconds), 480);
  assert.equal(pushes.length, 0);

  const pushTimer = timers.find((timer) => timer.ms === 180000);
  const endTimer = timers.find((timer) => timer.ms === 480000);
  assert.ok(pushTimer);
  assert.ok(endTimer);
  await pushTimer.fn();
  assert.equal(pushes[0].payload.aps.event, 'update');
  assert.equal(pushes[0].payload.aps['content-state'].minutes, 5);
  assert.equal(pushes[0].payload.aps['content-state'].text, 'About 5 minutes away');
  assert.equal(pushes[0].topic, 'mo.mbka.bus.push-type.liveactivity');
  assert.doesNotMatch(JSON.stringify(pushes[0].payload), /stopsAway|stopCount|stopsLeft/);

  await endTimer.fn();
  assert.equal(pushes[1].payload.aps.event, 'end');
  assert.equal(pushes[1].payload.aps['content-state'].minutes, 0);
  assert.equal(pushes[1].payload.aps['content-state'].text, 'Arrived');
  assert.doesNotMatch(JSON.stringify(pushes[1].payload), /stopsAway|stopCount|stopsLeft/);

  const soon = [];
  const soonBook = createBoardingReminders({
    now: () => 2_000_000,
    loadSegments: () => [{ fromSeq: 1, toSeq: 2, travelSeconds: 200, dwellSeconds: 15 }],
    credentials: () => ({ configured: true, bundleId: 'mo.mbka.bus', sandbox: false }),
    setTimer: (fn, ms) => {
      soon.push({ ms, fn });
      return soon.length;
    },
    clearTimer: () => {},
    sendPush: async (message) => {
      soon.push({ message });
      return { sent: true };
    },
  });
  const immediate = await soonBook.register({
    reminderId: 'soon',
    route: '3A',
    dir: 0,
    targetSeq: 2,
    lat: north(0),
    lng,
    lang: 'en',
    activityToken: 'activity-token',
    stops: [stop(1, 0), stop(2, 500)],
  });
  assert.equal(immediate.body.pushDelaySeconds, 0);
  assert.equal(immediate.body.minutes, 3);
  assert.equal(immediate.body.text, 'About 3 minutes away');
  const sent = soon.find((item) => item.message);
  assert.equal(sent.message.payload.aps['content-state'].minutes, 3);
  assert.equal(Math.round(immediate.body.endDelaySeconds), 200);
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
  assert.equal(timers, 2);
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

test('planReminder uses five minutes as the push point', () => {
  const later = planReminder(8 * 60);
  assert.equal(later.pushDelaySeconds, 3 * 60);
  assert.equal(later.pushMinutes, 5);
  assert.equal(later.endDelaySeconds, 8 * 60);
  const close = planReminder(200);
  assert.equal(close.pushDelaySeconds, 0);
  assert.equal(close.pushMinutes, 3);
  assert.equal(close.minutesNow, 3);
});
