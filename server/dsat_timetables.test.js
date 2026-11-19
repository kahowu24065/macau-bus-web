'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  SCHEMA,
  MIN_ROUTES,
  FREQUENCY_PATHS,
  validateDocument,
  createHandler,
  mountDsatTimetables,
} = require('./dsat_timetables');

const samplePath = path.join(__dirname, 'dsat_timetables.json');

function band(time, freq, title) {
  return {
    app_frequency: {
      sections: [
        {
          title: title || '2026年11月19日',
          directions: [
            { rows: [{ '服務時間': time, '班次(分鐘)': freq }] },
          ],
        },
      ],
    },
  };
}

function document(routes, schema) {
  return {
    schema: schema === undefined ? SCHEMA : schema,
    routes,
  };
}

function fillers(count, extra) {
  const routes = {};
  for (let i = 0; i < count; i += 1) routes[`F${i}`] = band('06:00-07:00', '10-12');
  Object.assign(routes, extra || {});
  return routes;
}

function fakeApp() {
  const routes = [];
  return {
    routes,
    get(routePath, handler) {
      routes.push({ routePath, handler });
    },
  };
}

function call(handler) {
  const res = {
    statusCode: 0,
    headers: {},
    body: null,
    setHeader(name, value) { this.headers[name] = value; },
    end(payload) { this.body = payload; },
  };
  handler({}, res);
  const text = Buffer.isBuffer(res.body) ? res.body.toString('utf8') : String(res.body);
  return { res, text };
}

test('constants match the app contract', () => {
  assert.equal(SCHEMA, 'dsat-app-frequency-v1');
  assert.equal(MIN_ROUTES, 50);
  assert.deepEqual(FREQUENCY_PATHS, ['/api/dsat_timetables.json', '/dsat_timetables.json']);
  const source = fs.readFileSync(path.join(__dirname, 'dsat_timetables.js'), 'utf8');
  assert.equal(source.includes('motransportinfo'), false);
  assert.equal(source.includes('bis.dsat.gov.mo'), false);
  assert.equal(source.includes("'/api/timetable.json'"), false);
  assert.equal(source.includes('"/api/timetable.json"'), false);
});

test('the sample file is the full frequency document, including 12T and 31T', () => {
  const decoded = JSON.parse(fs.readFileSync(samplePath, 'utf8'));
  assert.equal(validateDocument(decoded), null);
  assert.equal(decoded.route_count, Object.keys(decoded.routes).length);
  assert.ok(decoded.route_count >= MIN_ROUTES);
  for (const id of ['12T', '31T']) {
    const route = decoded.routes[id];
    assert.equal(route.circular, true);
    assert.equal(route.app_frequency.sections.length, 2);
    assert.equal(route.app_frequency.sections[0].directions.length, 1);
    assert.deepEqual(route.app_frequency.sections[0].directions[0].rows, [
      { '服務時間': '06:00-00:30', '班次(分鐘)': '12-20' },
    ]);
    assert.equal(route.app_frequency.sections[0].title, '2026年11月19-21日');
    assert.deepEqual(route.app_frequency.sections[1].directions[0].rows, [
      { '服務時間': '06:00-19:00', '班次(分鐘)': '12-20' },
    ]);
    assert.equal(route.app_frequency.sections[1].title, '2026年11月22日');
  }
});

test('short, wrong, or window-only files are refused', () => {
  assert.equal(validateDocument(null), 'dsat_timetables_invalid');
  assert.equal(validateDocument({ schema: SCHEMA }), 'dsat_timetables_invalid');
  assert.equal(
    validateDocument(document(fillers(MIN_ROUTES), 'other')),
    'dsat_timetables_invalid',
  );
  assert.equal(
    validateDocument(document(fillers(MIN_ROUTES - 1))),
    'dsat_timetables_too_small',
  );
  const windows = {};
  for (let i = 0; i < 80; i += 1) windows[`1A_${i}`] = { startTime: '06:00', endTime: '00:30' };
  assert.equal(validateDocument({ date: '20261119', routes: windows }), 'dsat_timetables_invalid');
  assert.equal(validateDocument(document(windows)), 'dsat_timetables_too_small');
  const lists = {};
  for (let i = 0; i < 80; i += 1) lists[`R${i}`] = { directions: [{ rows: [] }] };
  assert.equal(validateDocument(document(lists)), 'dsat_timetables_too_small');
  const legacy = fillers(MIN_ROUTES - 1, {
    LEG: { directions: { 0: { sections: [] } } },
  });
  assert.equal(validateDocument(document(legacy)), null);
});

test('the handler serves the file and re-reads it on the next request', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dsat-timetables-'));
  const filePath = path.join(dir, 'dsat_timetables.json');
  const first = document(fillers(MIN_ROUTES, { AA: band('06:00-07:00', '9-11') }));
  fs.writeFileSync(filePath, JSON.stringify(first));

  const app = fakeApp();
  const mounted = mountDsatTimetables(app, { filePath });
  assert.equal(mounted.filePath, filePath);
  assert.deepEqual(app.routes.map((route) => route.routePath), FREQUENCY_PATHS);

  const ok = call(app.routes[0].handler);
  assert.equal(ok.res.statusCode, 200);
  assert.equal(ok.res.headers['Content-Type'], 'application/json; charset=utf-8');
  assert.equal(ok.res.headers['Cache-Control'], 'public, max-age=60');
  assert.equal(ok.text, JSON.stringify(first));
  assert.equal(ok.text.includes('"AA"'), true);

  const second = document(fillers(MIN_ROUTES, { BB: band('08:00-09:00', '4-6') }));
  fs.writeFileSync(filePath, JSON.stringify(second));
  const again = call(app.routes[1].handler);
  assert.equal(again.res.statusCode, 200);
  assert.equal(again.text.includes('"BB"'), true);
  assert.equal(again.text.includes('"AA"'), false);

  fs.writeFileSync(filePath, '{');
  const invalid = call(createHandler(filePath));
  assert.equal(invalid.res.statusCode, 503);
  assert.deepEqual(JSON.parse(invalid.text), { success: false, error: 'dsat_timetables_invalid' });

  fs.writeFileSync(filePath, JSON.stringify(document(fillers(3))));
  const small = call(createHandler(filePath));
  assert.equal(small.res.statusCode, 503);
  assert.deepEqual(JSON.parse(small.text), { success: false, error: 'dsat_timetables_too_small' });

  const missing = call(createHandler(path.join(dir, 'missing.json')));
  assert.equal(missing.res.statusCode, 503);
  assert.deepEqual(JSON.parse(missing.text), { success: false, error: 'dsat_timetables_unavailable' });
});

test('the sample answers 200 and the checker accepts it', () => {
  const served = call(createHandler(samplePath));
  assert.equal(served.res.statusCode, 200);
  assert.equal(served.text, fs.readFileSync(samplePath, 'utf8'));
  const report = JSON.parse(execFileSync(process.execPath, [path.join(__dirname, 'dsat_timetables.js')], {
    encoding: 'utf8',
  }));
  assert.equal(report.ok, true);
  assert.equal(report.has12T, true);
  assert.equal(report.has31T, true);
  assert.ok(report.routes >= MIN_ROUTES);
});
