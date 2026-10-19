# Oracle deploy: route shapes from ROUTE_NETWORK

The Flutter app calls `GET https://macaubus-kat1.com/api/route-shape?route={ROUTE}&dir={0|1}`.

That handler is **not** running from this git repo. `server.js` lives only on the Oracle host (`~/macau-bus`). Copy the module below onto that host and wire it in `server.js`. Do not fetch motransportinfo, and do not keep serving GPX from `/api/bus-gpx`.

Shapefile date in the app attribution: **2026-09-25**. Source name: **澳門特別行政區政府數據開放平台**.

## Files to put on the server

Upload the 2026-09-25 ExportShapeFile set into the directory that already has `BUS_POLE.shp` (this was `~/macau-bus`):

- `ROUTE_NETWORK.shp`, `.dbf`, `.shx` (`.prj` / `.cpg` if the export includes them)
- `BUS_ROUTE_SEQ.dbf` (and `.shp` if present)

Leave `BUS_POLE` where the existing stop code already reads it. This module does not open `BUS_POLE`. This repo does not contain `server.js`, so the current `BUS_POLE` read was not changed.

Copy `server/route_shape.js` from this repo to `~/macau-bus/route_shape.js`. The module requires `proj4`, which the existing `BUS_POLE` code in `server.js` already uses. If `require('proj4')` fails, run `npm install proj4` in `~/macau-bus`.

## Edit `~/macau-bus/server.js`

1. Delete the `/api/bus-gpx` (or `/bus-gpx`) handler, including any request to `motransportinfo.com` and any read of `*.gpx`.
2. On the same router that serves `/api/bus-stops`, add:

```js
const { mountRouteShape, mountDisabledBusGpx } = require('./route_shape');

// 410. Nothing proxies the old GPX URL.
mountDisabledBusGpx(app);

mountRouteShape(app, {
  shapeDir: "/home/ubuntu/macau-bus",
  dataDate: "2026-09-25",
});
```

`shapeDir` and `dataDate` must be quoted strings. Unquoted values are not valid JavaScript and crashed pm2. Use the real shapefile directory if it is not `/home/ubuntu/macau-bus`. `shapeDir` can also be set with the `SHAPE_DIR` environment variable.

`mountRouteShape` registers `GET /api/route-shape` and `GET /route-shape`. The app uses `/api/route-shape`.

## What the join does

- Keep `BUS_ROUTE_SEQ` rows whose `ROUTE_NOS` equals the requested route (also splits combined values such as `1A,3`).
- If a direction column exists (`DIR`, `DIRECTION`, …) and has two values, `dir=0` is the lower/outbound value and `dir=1` the other. A single direction (circular routes) is returned for both.
- Order by `SEQ` (or `SEQUENCE` / `ROUTE_SEQ` when that is the column name).
- Look up each `NETWORK_ID` on `ROUTE_NETWORK` and chain polylines, flipping an edge when its far end is the one that touches the previous vertex. An edge that does not meet the previous vertex starts another line. Those gaps are not drawn. A step that reverses across a short connector, or that runs off a teleport with no road continuation, is dropped as well, so a chord across water or bare landfill is not stroked. Colinear bridge spans stay in the line.
- If that chain shatters (many pieces) and some other two-valued column separates the rows into directions that reconnect, `dir=0` / `dir=1` follow that column. A route that already chains, such as N3, is not split.
- A code like `102X` with no rows is served from `102`.
- Respond with `{ success, lines: [[{ lat, lng }, ...], ...], points, source: "ROUTE_NETWORK", attribution, dataDate }`. `points` is the longest line. `lines` is every piece. The app draws `lines`.
- `ROUTE_NETWORK` coordinates are Macau Grid meters (a sample vertex is about x=19956, y=19416), not WGS84. The module projects them with the same `proj4` definition and offsets as `BUS_POLE` in `server.js` (`MACAU_LAT_OFFSET` 0.00034, `MACAU_LNG_OFFSET` 0.00048). Vertices that are already longitude/latitude around Macau are left unchanged. Anything else still returns `crs_not_wgs84`.

If the DBF uses different column names, `node route_shape.js --shape-dir ~/macau-bus --inspect` prints the names it found and the ones it selected. A missing `ROUTE_NOS` or `NETWORK_ID` returns HTTP 503 `unexpected_fields` plus the real column list.

## Restart and check

Restart the Node process that already serves `/api/bus-stops` (however it is supervised today).

```bash
node ~/macau-bus/route_shape.js --shape-dir ~/macau-bus --inspect
node ~/macau-bus/route_shape.js --shape-dir ~/macau-bus --route 1A --route-dir 0
curl -sS 'http://127.0.0.1:PORT/api/route-shape?route=1A&dir=0' | head -c 400
curl -sS -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:PORT/api/bus-gpx?route=1A&dir=0'
```

The shape request should be HTTP 200 with `"source":"ROUTE_NETWORK"`. The old GPX path should be HTTP 410. Then the same `/api/route-shape` URL must answer on `https://macaubus-kat1.com` (Cloudflare in front of this origin). The app draws those `points` and does not fall back to any other host.

## Boarding reminder

The phone sends one `POST /api/boarding-reminder` with the single chosen bus's coordinates and the stop coordinates it already has. Copy `server/boarding_reminder.js` to `~/macau-bus/boarding_reminder.js` and mount it on the same app as `/api/bus-stops`:

This repo does not contain `server.js`. The mount below is what `~/macau-bus/server.js` runs. `learnedEta` is the object already in that file. Without `loadSegments`, the module only reads `segment_times.json` and returns `segment_times_missing` for routes that exist only in `learned_eta` (route 102 was one of those).

```js
mountBoardingReminder(app, {
  shapeDir: __dirname,
  loadSegments: (route, dir) => {
    const d = (dir === "A" || dir === "a") ? 0 : (dir === "B" || dir === "b") ? 1 : dir;
    const stopCount = typeof learnedEta.routeDirStopCount === "function"
      ? learnedEta.routeDirStopCount(route, d) : 0;
    if (stopCount < 2) return null;
    const hops = learnedEta.getSegmentSeconds(route, d, 1, stopCount);
    if (!hops) return null;
    const segs = [];
    for (let i = 0; i < hops.length; i++) {
      if (hops[i] == null) continue;
      segs.push({
        fromSeq: i + 1,
        toSeq: i + 2,
        travelSeconds: hops[i],
        dwellSeconds: 25,
      });
    }
    return segs.length ? segs : null;
  },
});
```

`segmentsFromLearnedEta` in `boarding_reminder.js` is that same mapping. Dir `A`/`a` is 0 and `B`/`b` is 1. A null hop is skipped. Each hop's dwell is 25 seconds, and dwell is not added at the target stop. `travelSeconds` includes lights and congestion. If `learned_eta` has no chain, the route still returns `segment_times_missing`. `segment_times.json` (or `SEGMENT_TIMES_PATH`) is used only when `loadSegments` is omitted.

`express.json()` must already be parsing the body. The module does not call motransportinfo. The module does not import `estimateLiveSeconds`; that name is not exported here.

```json
{ "3A": { "0": [ { "fromSeq": 1, "toSeq": 2, "travelSeconds": 90, "dwellSeconds": 20 } ] } }
```

While the reminder is active, the process sends an Apple Live Activity update about every 20 seconds (`apns-push-type: liveactivity`, topic `mo.mbka.bus.push-type.liveactivity`). Each update is the original remaining time minus elapsed wall time, as predicted minutes and a sentence that names the stop. It does not call the transport bureau again. An end push is sent when that countdown reaches the stop. The timer is in memory, so the Node process has to stay up. `POST /api/boarding-reminder/cancel` clears it, and a later tick does not push. The same `reminderId` does not schedule a second timer. A later POST with that same id and `activityToken` stores the token. If an update was already due and had no token, that POST sends the current countdown. A new reminder that reuses the same activity token or push-to-start token cancels the older one.

Apple push is sent only when `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_KEY_P8` or `APNS_KEY_PATH` are set. `APNS_USE_SANDBOX=1` uses the sandbox host. Do not invent a key. Without those values the reminder is still stored and `pushConfigured` is false.
