'use strict';

/**
 * Official DSAT frequency bands for the in-app timetable dialog.
 *
 *   GET /api/dsat_timetables.json
 *   GET /dsat_timetables.json
 *
 * The body is the dsat-app-frequency-v1 document, the same shape as
 * assets/dsat_timetables.json. The Flutter client loads that asset first,
 * then replaces its in-memory map when this response is HTTP 200, not a
 * Cloudflare challenge, schema is dsat-app-frequency-v1, and at least
 * MIN_ROUTES entries have app_frequency (or a legacy directions object).
 *
 * This is not /api/timetable.json. That endpoint stays the compact
 * { date, routes: { ROUTE_DIR: { startTime, endTime } } } first/last windows.
 *
 * The file is read on every request, so an edit is visible without a process
 * restart. Cache-Control is one minute. Keep any Cloudflare cache of this
 * path at least that short; the app itself retries at most every 30 minutes.
 *
 * Does not request the transport bureau or any other host.
 * Drop-in for the Oracle host. See server/ORACLE_DEPLOY.md.
 */

const fs = require('fs');
const path = require('path');

const SCHEMA = 'dsat-app-frequency-v1';
const MIN_ROUTES = 50;
const FREQUENCY_PATHS = ['/api/dsat_timetables.json', '/dsat_timetables.json'];

function isPlainObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function usableRoute(value) {
  if (!isPlainObject(value)) return false;
  if (isPlainObject(value.app_frequency)) return true;
  return isPlainObject(value.directions) && Object.keys(value.directions).length > 0;
}

/**
 * @returns {string|null} error code, or null when [decoded] is safe to serve
 * and safe for the app to swap in.
 */
function validateDocument(decoded) {
  if (!isPlainObject(decoded)) return 'dsat_timetables_invalid';
  if (decoded.schema !== SCHEMA) return 'dsat_timetables_invalid';
  if (!isPlainObject(decoded.routes)) return 'dsat_timetables_invalid';
  let usable = 0;
  for (const value of Object.values(decoded.routes)) {
    if (usableRoute(value)) usable += 1;
  }
  if (usable < MIN_ROUTES) return 'dsat_timetables_too_small';
  return null;
}

function fail(code) {
  const error = new Error(code);
  error.code = code;
  return error;
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

function sendRaw(res, status, body, headers) {
  if (typeof res.status === 'function' && typeof res.set === 'function' && typeof res.send === 'function') {
    let chain = res.status(status);
    for (const [key, value] of Object.entries(headers)) chain = chain.set(key, value);
    chain.send(body);
    return;
  }
  res.statusCode = status;
  if (typeof res.setHeader === 'function') {
    for (const [key, value] of Object.entries(headers)) res.setHeader(key, value);
  }
  res.end(body);
}

function createHandler(filePath) {
  return function dsatTimetablesHandler(req, res) {
    let raw;
    try {
      raw = fs.readFileSync(filePath);
      const decoded = JSON.parse(raw.toString('utf8'));
      const problem = validateDocument(decoded);
      if (problem) throw fail(problem);
    } catch (err) {
      let code = 'dsat_timetables_unavailable';
      if (err instanceof SyntaxError) code = 'dsat_timetables_invalid';
      else if (err && typeof err.code === 'string' && err.code.startsWith('dsat_timetables_')) {
        code = err.code;
      }
      sendJson(res, 503, { success: false, error: code });
      return;
    }
    sendRaw(res, 200, raw, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=60',
    });
  };
}

function mountDsatTimetables(app, options = {}) {
  const filePath = options.filePath
    || process.env.DSAT_TIMETABLES_PATH
    || path.join(__dirname, 'dsat_timetables.json');
  const handler = createHandler(filePath);
  const paths = options.paths || FREQUENCY_PATHS;
  for (const routePath of paths) app.get(routePath, handler);
  return { handler, filePath };
}

function resolveDefaultPath(argv) {
  const fromFlag = argv.indexOf('--file');
  if (fromFlag !== -1 && argv[fromFlag + 1]) return argv[fromFlag + 1];
  return process.env.DSAT_TIMETABLES_PATH || path.join(__dirname, 'dsat_timetables.json');
}

if (require.main === module) {
  const filePath = resolveDefaultPath(process.argv.slice(2));
  let decoded;
  try {
    decoded = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error(err instanceof SyntaxError ? 'dsat_timetables_invalid' : 'dsat_timetables_unavailable');
    process.exit(1);
  }
  const problem = validateDocument(decoded);
  if (problem) {
    console.error(problem);
    process.exit(1);
  }
  const routes = decoded.routes;
  console.log(JSON.stringify({
    ok: true,
    file: filePath,
    schema: decoded.schema,
    routes: Object.keys(routes).length,
    has12T: Boolean(routes['12T']),
    has31T: Boolean(routes['31T']),
  }));
}

module.exports = {
  SCHEMA,
  MIN_ROUTES,
  FREQUENCY_PATHS,
  validateDocument,
  usableRoute,
  createHandler,
  mountDsatTimetables,
};
