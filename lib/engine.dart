// GPS fixes in, laps out. A lap is timed at your pass by the start. Until GPS has seen a bend the
// track is assumed: a standard 400 m track, your way round, started at the finish line.
import 'dart:math' as math;

import 'track.dart';

export 'track.dart';

const double mile = 1609.344;
const double mpsToMph = 3600 / mile;
const double _earth = 6371008.8, _k = math.pi / 180;

class Fix {
  final double lat, lon, acc;
  final int t; // ms
  final double? spd, spdAcc; // m/s, the chip's Doppler speed when it has one
  const Fix(this.lat, this.lon, this.acc, this.t, {this.spd, this.spdAcc});
}

/// The fixes near the start, for timing a pass.
class Win {
  double d = double.infinity;
  int t;
  double since;
  final List<List<double>> pts = []; // [t, x, y] from the start
  int after = 0;
  Win(this.t, this.since);
}

/// Where you are in this lap: shown (the dot) and for distance.
class Frac {
  final double show, dist;
  const Frac(this.show, this.dist);
  static const zero = Frac(0, 0);
  List<double> toJson() => [show, dist];
  static Frac fromJson(List<dynamic> j) => Frac((j[0] as num).toDouble(), (j[1] as num).toDouble());
}

/// Your path, a point at least 8 m from the last, with the distance run to each.
class Dec {
  final List<Pt> p = [];
  final List<double> s = [];
  bool fromStart = true;
  bool add(Pt q) {
    if (p.isNotEmpty && q.dist(p.last) < 8) return false;
    s.add(p.isEmpty ? 0 : s.last + q.dist(p.last));
    p.add(q);
    return true;
  }

  void clear() {
    p.clear();
    s.clear();
    fromStart = false;
  }

  /// Index of the first point of the last len metres.
  int from(double len) {
    var i = s.length - 1;
    while (i > 0 && s.last - s[i - 1] <= len) {
      i--;
    }
    return i;
  }
}

class Run {
  final int lane, t0, defDir;
  final List<Map<String, dynamic>> tracks; // tracks seen before, looked for at the first fix
  final List<List<int>> pauses = []; // [from, to]
  Map<String, double>? ref;
  Pt? start, cur, last, prevP, lastSm;
  int prevT = 0, lastSmT = 0, lastFixT = 0, lastLapT, tInBand = 0;
  int? crossT, reachedEl;
  List<Pt> buf = [];
  double since = 0, total = 0;
  final List<Pt?> trace = []; // local metres east/north; null = pen lifted
  final List<int> laps = [];
  final List<double> lapGps = [], lapTop = [], vbuf = []; // lapTop: m/s, each lap's fastest moment
  bool armed = false;
  Win? win;
  double top = 0, lapTopNow = 0, speedNow = 0; // m/s
  double odo = 0, odoInBand = 0; // all distance moved, and at the last fix on the track
  Frac fracInBand = Frac.zero;

  Oval oval; // the line you run: your lane of a standard track, or the track as sensed
  Geo? geo; // where that oval lies on the ground
  int dir; // 1 counter-clockwise, -1 clockwise
  String sense = 'default'; // default | saved | sensed | refined
  double? uStart; // where the start is on the oval, once known
  int? sensedAt; // when the drawing last changed
  double senseS = 0, triedS = 0, anchorS = 0;
  int refinedAt = -1; // laps when last fitted whole
  bool anchored = true; // laps count from the start (false: you started off the track)
  bool notTrack = false; // going round a loop no track is the shape of

  bool off = false;
  int farN = 0, backN = 0, joinN = 0;
  double offM = 0, corrM = 0, leaveLapM = 0;
  Frac leaveFrac = Frac.zero;
  final List<List<num>> offSpans = []; // [from t, to t (-1 while off), offM at from, offM at to]
  final Dec dec = Dec();

  Run(this.lane, this.t0, {this.dir = 1, this.tracks = const []}) : oval = Oval.lane(lane), defDir = dir, lastLapT = t0;

  double get L => oval.perim;

  Map<String, dynamic> toJson() => {
    'lane': lane,
    't0': t0,
    'pauses': pauses,
    'ref': ref,
    'start': start?.toJson(),
    'since': since,
    'total': total,
    'trace': [for (final q in trace) q?.toJson()],
    'laps': laps,
    'lapGps': lapGps,
    'lapTop': lapTop,
    'armed': armed,
    'lastLapT': lastLapT,
    'reachedEl': reachedEl,
    'top': top,
    'lapTopNow': lapTopNow,
    'oval': [oval.r, oval.st],
    'geo': geo?.toJson(),
    'dir': dir,
    'defDir': defDir,
    'sense': sense,
    'uStart': uStart,
    'sensedAt': sensedAt,
    'anchored': anchored,
    'off': off,
    'offM': offM,
    'corrM': corrM,
    'leaveLapM': leaveLapM,
    'leaveFrac': leaveFrac.toJson(),
    'offSpans': offSpans,
    'notTrack': notTrack,
  };

  static Run fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num? ?? 0).toDouble();
    int? i(String k) => (j[k] as num?)?.toInt();
    List<double> ds(String k) => [for (final v in j[k] as List? ?? []) (v as num).toDouble()];
    final o = j['oval'] as List;
    return Run(j['lane'] as int, j['t0'] as int, dir: i('defDir') ?? 1)
      ..pauses.addAll([
        for (final p in j['pauses'] as List) [(p[0] as num).toInt(), (p[1] as num).toInt()],
      ])
      ..ref = (j['ref'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      ..start = j['start'] == null ? null : Pt.fromJson(j['start'])
      ..since = d('since')
      ..total = d('total')
      ..trace.addAll([for (final q in j['trace'] as List) q == null ? null : Pt.fromJson(q)])
      ..trace.add(null) // whatever happened while the app was closed is not drawn
      ..laps.addAll([for (final t in j['laps'] as List) (t as num).toInt()])
      ..lapGps.addAll(ds('lapGps'))
      ..lapTop.addAll(ds('lapTop'))
      ..armed = j['armed'] as bool
      ..lastLapT = i('lastLapT')!
      ..reachedEl = i('reachedEl')
      ..top = d('top')
      ..lapTopNow = d('lapTopNow')
      ..oval = Oval((o[0] as num).toDouble(), (o[1] as num).toDouble())
      ..geo = j['geo'] == null ? null : Geo.fromJson(j['geo'] as List)
      ..dir = i('dir')!
      ..sense = j['sense'] as String
      ..uStart = (j['uStart'] as num?)?.toDouble()
      ..sensedAt = i('sensedAt')
      ..anchored = j['anchored'] as bool
      ..notTrack = j['notTrack'] as bool? ?? false
      ..off = j['off'] as bool
      ..offM = d('offM')
      ..corrM = d('corrM')
      ..leaveLapM = d('leaveLapM')
      ..leaveFrac = Frac.fromJson(j['leaveFrac'] as List)
      ..offSpans.addAll([
        for (final s in j['offSpans'] as List) [for (final v in s as List) v as num],
      ])
      ..dec.fromStart = false;
  }
}

Pt _toXY(Map<String, double> ref, double lat, double lon) =>
    Pt((lon - ref['lon']!) * _k * _earth * math.cos(ref['lat']! * _k), (lat - ref['lat']!) * _k * _earth);

/// Running time at t, stops left out.
int activeMs(Run r, int t) {
  var ms = t - r.t0;
  for (final p in r.pauses) {
    if (t > p[0]) ms -= math.min(p[1], t) - p[0];
  }
  return math.max(0, ms);
}

/// GPS reads long on a loop: once a lap is measured, the dot goes by what GPS says a lap is.
double gpsLap(Run r) {
  if (r.lapGps.isEmpty) return r.L;
  final s = [...r.lapGps]..sort();
  return math.min(1.6 * r.L, math.max(0.8 * r.L, s[s.length >> 1]));
}

void _closeLap(Run r, int t, double sinceAt, bool measured) {
  r.laps.add(t);
  r.lastLapT = t;
  if (measured) r.lapGps.add(sinceAt);
  r.lapTop.add(r.lapTopNow);
  r.lapTopNow = 0;
  r.since = math.max(0, r.since - sinceAt);
  r.win = null;
  r.crossT = null;
}

/// The moment you crossed: a straight-line fit of the fixes near the start along your way of travel.
int passTime(Win w) {
  final pts = w.pts, n = pts.length;
  if (n < 4) return w.t;
  final a = pts.first, b = pts.last;
  final ux = b[1] - a[1], uy = b[2] - a[2], len = math.sqrt(ux * ux + uy * uy);
  if (len < 8) return w.t;
  var st = 0.0, ss = 0.0, stt = 0.0, sts = 0.0;
  for (final p in pts) {
    final tt = (p[0] - a[0]) / 1000, s = (p[1] * ux + p[2] * uy) / len;
    st += tt;
    ss += s;
    stt += tt * tt;
    sts += tt * s;
  }
  final v = (n * sts - st * ss) / (n * stt - st * st);
  if (!(v > 0.5)) return w.t;
  final tc = a[0] + (st / n - (ss / n) / v) * 1000;
  return tc >= a[0] && tc <= b[0] ? tc.round() : w.t;
}

void closeWindow(Run r) {
  final w = r.win!;
  r.win = null;
  final t = passTime(w);
  if (t - r.lastLapT < r.L / 9 * 1000) return; // quicker than a world record: not a lap
  _closeLap(r, t, w.since, true);
  r.armed = false;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s.length.isOdd ? s[s.length >> 1] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

double _startR(Run r, double acc) => math.min(0.09 * r.L, math.max(20.0, 2.5 * acc));
double _gate(Run r, double acc) => math.max(0.15 * r.L, _startR(r, acc) + 15);

/// Further from the last good fix than anyone runs (12 m/s): a bad fix. Still that far 10 s on, GPS
/// really moved (a stale first fix, a GPS simulator): the jump is lifted over like a gap and never
/// counted as running. If nothing was run yet, the run starts at the new place.
bool _jumped(Run r, Pt p, int t) {
  if (r.prevP == null || p.dist(r.prevP!) / math.max((t - r.prevT) / 1000, 0.2) <= 12) return false;
  if (t - r.prevT < 10000) return true;
  _lift(r);
  if (r.laps.isEmpty && !r.off && r.total < 20 && r.odo < 20) {
    r
      ..ref = null
      ..start = null
      ..cur = null
      ..lastFixT = 0
      ..top = 0
      ..lapTopNow = 0
      ..speedNow = 0
      ..oval = Oval.lane(r.lane)
      ..geo = null
      ..dir = r.defDir
      ..sense = 'default'
      ..uStart = null
      ..sensedAt = null
      ..anchored = true
      ..tInBand = 0
      ..odoInBand = 0
      ..fracInBand = Frac.zero;
    r.trace.clear();
    r.dec.fromStart = true;
  }
  return false;
}

/// Feed one fix; returns how many laps it completed.
int feed(Run r, Fix fix) {
  if (!(fix.acc <= 30)) return 0;
  if (r.ref != null && _jumped(r, _toXY(r.ref!, fix.lat, fix.lon), fix.t)) return 0;
  final first = r.ref == null;
  r.ref ??= {'lat': fix.lat, 'lon': fix.lon};
  final p = _toXY(r.ref!, fix.lat, fix.lon);
  r.prevP = p;
  r.prevT = fix.t;
  r.start ??= p;
  if (first) _knownTrack(r);
  r.buf.add(p);
  if (r.buf.length > 5) r.buf.removeAt(0);
  final sm = Pt(
    r.buf.map((q) => q.x).reduce((a, b) => a + b) / r.buf.length,
    r.buf.map((q) => q.y).reduce((a, b) => a + b) / r.buf.length,
  );
  r.cur = sm;

  // speed: the chip's Doppler when it trusts it, else smoothed movement; a median of 3 drops spikes
  final doppler = fix.spd != null && fix.spd! >= 0 && (fix.spdAcc == null || fix.spdAcc! <= 1.5);
  final still = fix.spd != null && fix.spd! < 0.6;
  var v = doppler ? fix.spd : null;
  if (v == null && r.lastSm != null && fix.t > r.lastSmT) v = sm.dist(r.lastSm!) / ((fix.t - r.lastSmT) / 1000);
  r.lastSm = sm;
  r.lastSmT = fix.t;
  if (v != null && v < 13) {
    r.vbuf.add(v);
    if (r.vbuf.length > 3) r.vbuf.removeAt(0);
    r.speedNow = _median(r.vbuf);
    if (r.vbuf.length == 3) {
      r.top = math.max(r.top, r.speedNow);
      r.lapTopNow = math.max(r.lapTopNow, r.speedNow);
    }
  }

  final lt = r.trace.isEmpty ? null : r.trace.last;
  if (!still && (lt == null || lt.dist(sm) >= 3)) {
    r.trace.add(Pt((sm.x * 10).round() / 10, (sm.y * 10).round() / 10));
    if (r.dec.add(sm)) _sense(r, fix.t);
  }
  if (r.last == null) {
    r.last = sm;
    return 0;
  }
  _offCheck(r, fix, p, sm);
  final before = r.laps.length, lg = gpsLap(r);
  final counting = !r.off && r.anchored;
  final d = sm.dist(r.last!);
  final dt = r.lastFixT == 0 ? 0.0 : (fix.t - r.lastFixT) / 1000;
  r.lastFixT = fix.t;
  final moved = !still && d >= math.max(6, fix.acc);
  if (moved) r.total += d;
  // distance moved: Doppler speed over time when there is one (a noisy path reads long)
  final step = doppler && dt > 0 && dt <= 5 ? (still ? 0.0 : fix.spd! * dt) : (moved ? d : null);
  if (step != null) r.odo += step;
  if (!counting) {
    if (step != null) {
      r.offM += step;
      r.last = sm;
    }
    return 0;
  }
  if (moved) {
    r.last = sm;
    final was = r.since;
    r.since += d;
    if (was < lg && r.since >= lg && r.crossT == null) r.crossT = fix.t;
  }
  final ds = p.dist(r.start!), rr = _startR(r, fix.acc), gate = _gate(r, fix.acc);
  if (!r.armed && ds > gate) r.armed = true;
  if (r.armed) {
    // open near the start, close only once clearly past it (one noisy fix must not end the pass)
    if (r.win == null && ds < rr) r.win = Win(fix.t, r.since);
    final w = r.win;
    if (w != null) {
      if (ds < rr + 10) {
        w.pts.add([fix.t.toDouble(), p.x - r.start!.x, p.y - r.start!.y]);
        if (ds < w.d) {
          w.d = ds;
          w.t = fix.t;
          w.since = r.since;
          w.after = 0;
        } else {
          w.after++;
        }
      }
      if ((ds >= rr + 10 && w.after >= 2) || (ds > w.d + 20 && w.after >= 4) || ds > rr + 30) closeWindow(r);
    }
    // the pass by the start was lost to a GPS gap (and never quicker than a world record)
    final at = r.crossT ?? fix.t;
    if (r.win == null && ds > gate && r.since > 1.5 * lg && at - r.lastLapT >= r.L / 9 * 1000) {
      _closeLap(r, at, lg, false);
    }
  }
  return r.laps.length - before;
}

/* ---------- the track: assumed, sensed, refined ---------- */

/// The oval of a kept track in your lane.
Oval trackOval(Map<String, dynamic>? t, int lane) => t == null || (t['std'] as bool? ?? true)
    ? Oval.lane(lane)
    : Oval((t['rk'] as num).toDouble() + laneRadius(lane) - kerbRadius, (t['st'] as num).toDouble());

Pt _centreOf(Run r, Map<String, dynamic> t) =>
    _toXY(r.ref!, (t['lat'] as num).toDouble(), (t['lon'] as num).toDouble());

/// A track seen before, within 200 m of where you start.
void _knownTrack(Run r) {
  Map<String, dynamic>? best;
  var bd = 200.0;
  for (final t in r.tracks) {
    final d = _centreOf(r, t).dist(r.start!);
    if (d < bd) {
      bd = d;
      best = t;
    }
  }
  if (best == null) return;
  final c = _centreOf(r, best);
  r.oval = trackOval(best, r.lane);
  r.geo = Geo.centred((best['a'] as num).toDouble(), c.x, c.y);
  r.dir = (best['dir'] as num? ?? r.dir).toInt();
  r.sense = 'saved';
  _placeStart(r);
}

/// Put the start on the oval, turned so the start is on the near (bottom) side. Kept: a run already
/// counting laps from its start keeps it, however far a noisy first fix sits from a refitted oval.
void _placeStart(Run r, {bool kept = false}) {
  var e = r.geo!.apply(r.start!);
  if (kept || r.oval.sd(e.x, e.y).abs() <= 15) {
    if (e.x < 0) {
      r.geo = r.geo!.flipped();
      e = r.geo!.apply(r.start!);
    }
    r.uStart = r.oval.uOf(e.x, e.y);
    r.anchored = true;
  } else {
    if (r.geo!.apply(r.cur ?? r.start!).x < 0) r.geo = r.geo!.flipped();
    r.uStart = null;
    r.anchored = false;
  }
}

double _gapM(Oval o, double a, double b) {
  final d = ((a - b) % 1 + 1) % 1;
  return math.min(d, 1 - d) * o.perim;
}

/// Sure enough to redraw: a close fit no other place or direction comes near, after a real bend.
bool sureFit(Reg g, {required bool fromStart}) =>
    g.rms <= 4.5 &&
    g.worst <= 12 && // a street corner is sharper than any bend
    g.altDir >= 1.6 * g.rms + 1.5 &&
    g.altPhase >= 1.6 * g.rms + 1.5 &&
    g.turned >= (fromStart ? 120 : 150) * math.pi / 180;

void _sense(Run r, int t) {
  final d = r.dec;
  switch (r.sense) {
    case 'refined':
      if (r.laps.length != r.refinedAt && r.laps.length <= 4) _refine(r, t);
    case 'saved':
      // a track seen before: check it is this one, and which way you go round it today
      if (!r.anchored || d.s.isEmpty) return;
      var i0 = d.from(160);
      while (i0 < d.s.length - 1 && d.s[i0] < r.anchorS) {
        i0++;
      }
      if (d.s.last - d.s[i0] < 40) return;
      var offBy = 0.0, du = 0.0;
      for (var i = i0; i < d.p.length; i++) {
        final e = r.geo!.apply(d.p[i]);
        offBy += r.oval.sd(e.x, e.y).abs();
        if (i > i0) {
          final e0 = r.geo!.apply(d.p[i - 1]);
          final x = r.oval.uOf(e.x, e.y) - r.oval.uOf(e0.x, e0.y);
          du += x - x.roundToDouble();
        }
      }
      if (offBy / (d.p.length - i0) > 12) {
        // not that track after all
        r
          ..sense = 'default'
          ..geo = null
          ..oval = Oval.lane(r.lane)
          ..uStart = null
          ..anchored = true
          ..dir = r.defDir;
        return;
      }
      if ((du * r.oval.perim).abs() < 30) return;
      final way = du >= 0 ? 1 : -1;
      if (way != r.dir) {
        r.dir = way;
        r.sensedAt = t;
      }
      r.sense = 'sensed';
      r.senseS = d.s.last;
    case 'default':
      if (d.s.isEmpty || d.s.last < 70 || r.notTrack) return;
      final g = _register(r);
      if (g != null && sureFit(g, fromStart: d.fromStart && d.from(320) == 0) && (!r.off || g.rms <= 3.5)) {
        _adopt(r, g, t);
      } else if ((r.laps.isNotEmpty || r.total >= 1.2 * r.L) && d.s.last - r.triedS >= 60) {
        r.triedS = d.s.last;
        _fitLoop(r, t); // no clean bend to go by: fit the whole loop
      }
    case 'sensed':
      if (r.laps.isNotEmpty || d.s.last - r.senseS >= 0.85 * r.oval.perim) {
        _refine(r, t);
      } else if (!r.off && d.s.last - r.triedS >= 40) {
        // until the whole loop is in, a surer fit that disagrees replaces the first
        r.triedS = d.s.last;
        final g = _register(r);
        if (g != null &&
            sureFit(g, fromStart: false) &&
            g.rms < 0.8 * fitRms(d.p.sublist(d.from(320)), r.oval, r.geo!)) {
          _adopt(r, g, t);
        }
      }
  }
}

/// The last 320 m of path laid onto the track: a standard one unless it plainly is not.
Reg? _register(Run r) {
  final d = r.dec, i0 = d.from(320);
  final pts = d.p.sublist(i0), s = d.s.sublist(i0), base = Oval.lane(r.lane);
  final g = register(pts, s, base, scales: const [1.0]);
  if (g == null || g.rms <= 4) return g;
  final any = register(pts, s, base);
  return any != null && any.rms < 0.5 * g.rms ? any : g;
}

void _adopt(Run r, Reg g, int t) {
  final wasDir = r.dir, wasU = r.uStart ?? r.oval.uFinish;
  r.oval = g.oval;
  r.geo = g.geo;
  r.dir = g.dir;
  r.sense = 'sensed';
  r.senseS = r.dec.s.last;
  _placeStart(r);
  if (r.dir != wasDir || !r.oval.standard || r.uStart == null || _gapM(r.oval, r.uStart!, wasU) > 25) r.sensedAt = t;
}

/// The trace, one point per 4 m patch (time spent in one place can't outweigh the track), near the oval.
List<Pt> _patches(Run r, {Geo? g, double near = 20}) {
  final seen = <int>{};
  return [
    for (final q in r.trace.whereType<Pt>())
      if (seen.add(((q.x / 4).floor() * 100003) ^ (q.y / 4).floor()) &&
          (g == null ||
              () {
                final e = g.apply(q);
                return r.oval.sd(e.x, e.y).abs() <= near;
              }()))
        q,
  ];
}

/// A track: bends of 15 to 60 m, straights up to 160 m. A loop round a park is not one.
bool _trackShape(Oval o) => o.r >= 15 && o.r <= 60 && o.st <= 160;

bool _standardShape(Oval o) =>
    (o.st - straight).abs() < 15 && o.r > kerbRadius - 3 && o.r < kerbRadius + trackWidth + 3;

/// How much of the oval the points go round (0..1).
double _coverage(List<Pt> q, Oval o, Geo g) {
  final bins = List.filled(36, false);
  for (final p in q) {
    final e = g.apply(p);
    if (o.sd(e.x, e.y).abs() < 8) bins[(o.uOf(e.x, e.y) * 36).floor() % 36] = true;
  }
  return bins.where((b) => b).length / 36;
}

/// A whole-loop fit: snap to the standard track if it is one, else keep the shape found.
void _take(Run r, ({Geo geo, Oval oval, double rms}) f, List<Pt> q) {
  final std = _standardShape(f.oval);
  r.oval = std ? Oval.lane(r.lane) : f.oval;
  r.geo = std ? icp(q, r.oval, f.geo) : f.geo;
  r.sense = 'refined';
  r.refinedAt = r.laps.length;
}

/// The oval along the long axis of the points.
Geo? _pcaGeo(List<Pt> q) {
  if (q.length < 20) return null;
  final a = longAxis(q);
  return Geo.centred(a.angle + math.pi / 2, a.x, a.y);
}

/// A lap or more of path: fit the whole loop, and decide whether it is a standard track.
void _refine(Run r, int t) {
  r.refinedAt = r.laps.length;
  final q = _patches(r, g: r.geo, near: 45);
  var f = fitShape(q, r.geo!, r.oval);
  final h = _pcaGeo(q);
  if (h != null) {
    final f2 = fitShape(q, h, Oval.lane(r.lane));
    if (f2 != null && (f == null || f2.rms < f.rms)) f = f2;
  }
  if (f == null || f.rms > 7 || !_trackShape(f.oval)) return;
  final wasStd = r.oval.standard;
  _take(r, f, q);
  if (r.anchored) _placeStart(r, kept: true);
  if (wasStd != r.oval.standard) r.sensedAt = t;
}

/// No clean bend to go by (GPS too rough): fit the whole loop from its long axis.
void _fitLoop(Run r, int t) {
  final q = _patches(r);
  if (q.length < 40) return;
  final f = fitShape(q, _pcaGeo(q)!, Oval.lane(r.lane));
  if (f == null || f.rms > 5 || _coverage(q, f.oval, f.geo) < 0.85) return;
  if (!_trackShape(f.oval)) {
    r.notTrack = true;
    return;
  }
  final wasDir = r.dir;
  _take(r, f, q);
  r.dir = loopDir(r.trace.whereType<Pt>().toList());
  _placeStart(r);
  if (r.dir != wasDir || !r.oval.standard || r.uStart == null || _gapM(r.oval, r.uStart!, r.oval.uFinish) > 25) {
    r.sensedAt = t;
  }
}

/// Before the track is known: you started at the finish line, heading into the bend, your way round.
Geo? defaultGeo(Run r) {
  if (r.start == null) return null;
  final far = r.trace.firstWhere((q) => q != null && q.dist(r.start!) >= 15, orElse: () => null);
  if (far == null) return null;
  final o = r.oval, u = o.uFinish, at = o.along(u), tg = o.tangentAt(u);
  final vx = far.x - r.start!.x, vy = -(far.y - r.start!.y);
  final a = math.atan2(tg.y * r.dir, tg.x * r.dir) - math.atan2(vy, vx);
  final c = math.cos(a), s = math.sin(a), fx = r.start!.x, fy = -r.start!.y;
  return Geo(c, s, at.x - (c * fx - s * fy), at.y - (s * fx + c * fy));
}

/// Where the drawing puts your path: the track once known, else the assumption.
Geo? drawGeo(Run r) => r.geo ?? defaultGeo(r);

double uStartShown(Run r) => r.uStart ?? r.oval.uFinish;

/* ---------- off the track ---------- */

/// About 160 m dead straight (155 m end to end, nothing more than 8 m off the line). A track's
/// straights are 84 m. GPS reads a path long, so the window is a little longer than 155 m.
bool straightRun(Dec d) {
  if (d.s.isEmpty || d.s.last < 170) return false;
  final i0 = d.from(170);
  final a = d.p[i0], b = d.p.last, len = a.dist(b);
  if (len < 155) return false;
  for (var i = i0 + 1; i < d.p.length - 1; i++) {
    final q = d.p[i];
    if (((b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)).abs() / len > 8) return false;
  }
  return true;
}

/// How far outside the track you are, in metres past its edge (negative: on it).
({double past, double fromLine})? offTrackBy(Run r, Pt sm) {
  final g = r.geo;
  if (g == null) return null;
  final e = g.apply(sm), d = r.oval.sd(e.x, e.y);
  final rk = r.oval.standard ? kerbRadius : r.oval.r - 0.3;
  final inner = rk - r.oval.r, outer = rk + trackWidth - r.oval.r;
  return (past: d > outer ? d - outer : (d < inner ? inner - d : -math.min(d - inner, outer - d)), fromLine: d);
}

/// Off: 160 m dead straight, or past the track's edge by 20 m or more (more in rough GPS) for 5 fixes.
void _offCheck(Run r, Fix fix, Pt p, Pt sm) {
  final line = straightRun(r.dec);
  final by = offTrackBy(r, sm);
  if (!r.off && by != null && by.past < 5) {
    r.odoInBand = r.odo;
    r.tInBand = fix.t;
    r.fracInBand = fracs(r);
  }
  // until a whole lap is fitted, the far side of the oval can be out by 20 m
  final room = r.sense == 'refined' ? math.max(20.0, 2.5 * fix.acc) : math.max(35.0, 3 * fix.acc);
  final far = r.notTrack || (by != null ? by.past > room : sm.dist(r.start!) > 230);
  if (!r.off) {
    r.farN = far ? r.farN + 1 : 0;
    if (r.farN >= 5 || line) _goOff(r, fix.t, from: by != null && !line);
  } else {
    // back on only onto a known track
    r.backN = !r.notTrack && by != null && by.past < 8 && !line ? r.backN + 1 : 0;
    if (r.backN >= 8) _goOn(r, fix.t, p);
  }
  if (!r.off && !r.anchored && by != null) {
    r.joinN = by.fromLine.abs() < 8 ? r.joinN + 1 : 0;
    if (r.joinN >= 3) _anchor(r, fix.t, p);
  }
}

double _uNow(Run r) {
  final e = r.geo!.apply(r.cur!);
  final u = (r.oval.uOf(e.x, e.y) - r.uStart!) * r.dir;
  return ((u % 1) + 1) % 1;
}

void _clearLaps(Run r) {
  r.laps.clear();
  r.lapGps.clear();
  r.lapTop.clear();
  r.since = 0;
}

void _goOff(Run r, int t, {bool from = false}) {
  // off by distance from the track: you left at the last fix on it, so count from there
  final f = from ? r.fracInBand : fracs(r);
  r.leaveFrac = f;
  r.leaveLapM = (r.laps.length + f.dist) * r.L;
  r.offSpans.add([from && r.tInBand > 0 ? r.tInBand : t, -1, r.offM, r.offM]);
  if (from) r.offM += math.max(0.0, r.odo - r.odoInBand);
  if (r.geo == null) {
    // no track was ever found: the whole distance is the chip's own, from the start
    if (r.notTrack) {
      _clearLaps(r);
      r.leaveFrac = Frac.zero;
      r.leaveLapM = 0;
    }
    r.corrM += r.odo - (r.leaveLapM + r.offM + r.corrM);
  }
  r
    ..off = true
    ..farN = 0
    ..backN = 0
    ..win = null
    ..armed = false
    ..crossT = null;
}

void _goOn(Run r, int t, Pt p) {
  r
    ..off = false
    ..backN = 0
    ..win = null
    ..crossT = null;
  if (r.offSpans.isNotEmpty) {
    r.offSpans.last[1] = t;
    r.offSpans.last[3] = r.offM;
  }
  if (!r.anchored) return; // joining the track for the first time: the anchor takes it from here
  // the distance carries on: you pick up the lap where you joined
  final u = r.geo != null && r.uStart != null ? _uNow(r) : 0.0;
  r.corrM += r.leaveLapM - (r.laps.length + u) * r.L;
  r.since = u * gpsLap(r);
  r.armed = p.dist(r.start!) > _gate(r, 10);
}

/// Joined the track from off it: this is the start line now, and what came before is GPS distance.
void _anchor(Run r, int t, Pt p) {
  r.offM += (r.laps.length + fracs(r).dist) * r.L;
  _clearLaps(r);
  r
    ..start = p
    ..armed = false
    ..win = null
    ..crossT = null
    ..lastLapT = t
    ..joinN = 0
    ..anchored = true
    ..anchorS = r.dec.s.isEmpty ? 0 : r.dec.s.last;
  _placeStart(r);
  r.sensedAt = t;
}

/// Stopped from a to b, then going again.
void resumeRun(Run r, int a, int b) {
  r.pauses.add([a, b]);
  _lift(r);
}

/// A break in the path: nothing measured across it.
void _lift(Run r) {
  r
    ..prevP = null
    ..buf = []
    ..last = null
    ..win = null
    ..crossT = null
    ..lastSm = null
    ..farN = 0
    ..backN = 0;
  r.vbuf.clear();
  r.dec.clear();
  r.trace.add(null); // lift the pen over the break
}

/// A stop at t: a pass by the start before t still counts, laps after t don't.
void stopAt(Run r, int t) {
  if (r.win != null && r.win!.t <= t) closeWindow(r);
  while (r.laps.isNotEmpty && r.laps.last > t) {
    r.laps.removeLast();
    if (r.lapTop.length > r.laps.length) r.lapTop.removeLast();
  }
}

/// Where you are in this lap. Off the track it holds where you left.
Frac fracs(Run r) {
  if (r.off) return r.leaveFrac;
  if (r.geo == null || r.uStart == null || r.cur == null) {
    final v = r.since / gpsLap(r);
    return Frac(math.min(v, 0.995), v); // the dot waits at the line; the distance does not
  }
  var u = _uNow(r);
  if (!r.armed && r.win == null && u > 0.5) u = 0; // still at the start, or just lapped
  if (r.win != null && u < 0.5) return Frac(u, 1 + u); // crossed; the lap counts in a moment
  return Frac(u, u);
}

class Stats {
  final int n, el; // n: laps, or lap equivalents of the distance once any of it was off the track
  final double show, dist, metres;
  final double? avgLap, mph, topMph;
  const Stats(this.n, this.el, this.show, this.dist, this.metres, this.avgLap, this.mph, this.topMph);
}

Stats stats(Run r, int t, Frac f) {
  final nGeo = r.laps.where((x) => x <= t).length, el = activeMs(r, t);
  final ff = nGeo == r.laps.length ? f : Frac.zero;
  final metres = math.max(0.0, (nGeo + ff.dist) * r.L + r.offM + r.corrM);
  final pure = r.offM == 0 && r.corrM == 0; // every metre was on the track
  return Stats(
    pure ? nGeo : (metres / r.L + 1e-9).floor(),
    el,
    ff.show,
    ff.dist,
    metres,
    pure ? (nGeo > 0 ? activeMs(r, r.laps[nGeo - 1]) / nGeo : null) : (metres >= r.L ? el * r.L / metres : null),
    metres >= 50 && el >= 15000 ? (metres / mile) / (el / 3.6e6) : null,
    r.top > 0 ? r.top * mpsToMph : null,
  );
}

/* ---------- tracks kept between runs ---------- */

/// The track this run found, to know it next time.
Map<String, dynamic>? trackOf(Run r, int now) {
  if (r.geo == null || r.ref == null || r.sense == 'default' || r.sense == 'saved') return null;
  final c = r.geo!.centre, lat0 = r.ref!['lat']!;
  return {
    'lat': lat0 + c.y / _earth / _k,
    'lon': r.ref!['lon']! + c.x / (_earth * math.cos(lat0 * _k)) / _k,
    'a': r.geo!.angle,
    'std': r.oval.standard,
    'st': r.oval.st,
    'rk': r.oval.standard ? kerbRadius : r.oval.r - (laneRadius(r.lane) - kerbRadius),
    'dir': r.dir,
    'u0': r.uStart,
    'used': now,
  };
}

/// Kept tracks with this one added, replacing the same track (centre within 60 m).
List<Map<String, dynamic>> withTrack(List<Map<String, dynamic>> tracks, Map<String, dynamic> t) {
  double d(Map<String, dynamic> a) {
    final dy = ((a['lat'] as num) - (t['lat'] as num)) * _k * _earth;
    final dx = ((a['lon'] as num) - (t['lon'] as num)) * _k * _earth * math.cos((t['lat'] as num) * _k);
    return math.sqrt(dx * dx + dy * dy);
  }

  return [
    t,
    for (final a in tracks)
      if (d(a) > 60) a,
  ].take(20).toList();
}

/* ---------- history ---------- */

Map<String, dynamic> historyEntry(Run r, int t, Frac? frac, String goal) {
  final s = stats(r, t, frac ?? fracs(r)), g = drawGeo(r);
  final route = r.geo == null ? r.offM > 0 || r.laps.isEmpty : r.offM > 0.5 * s.metres;
  final step = math.max(1, (r.trace.whereType<Pt>().length / 400).ceil());
  final pts = <List<double>?>[];
  var i = 0;
  for (final q in r.trace) {
    if (q == null) {
      pts.add(null);
    } else if (i++ % step == 0) {
      final p = route || g == null ? q : g.apply(q);
      pts.add([(p.x * 10).round() / 10, (p.y * 10).round() / 10]);
    }
  }
  final laps = <int>[];
  var prev = 0;
  for (final x in r.laps.where((x) => x <= t)) {
    final a = activeMs(r, x);
    laps.add(a - prev);
    prev = a;
  }
  return {
    'id': r.t0,
    'lane': r.lane,
    'el': s.el,
    'n': s.n,
    'metres': s.metres.round(),
    'mph': s.mph,
    'top': s.topMph,
    'goal': goal,
    'pts': pts,
    'laps': laps,
    'lapTop': [for (var i = 0; i < laps.length && i < r.lapTop.length; i++) (r.lapTop[i] * mpsToMph * 10).round() / 10],
    'tail': math.max(0, s.el - prev),
    'tailFrac': ((s.dist % 1) * 10).floor() / 10,
    'pauses': [
      for (final p in r.pauses.where((p) => p[0] <= t)) [activeMs(r, p[0]), p[1] - p[0]],
    ],
    'route': route,
    'L': r.L,
    'shape': [r.oval.r, r.oval.st],
    'dir': r.dir,
    'u0': uStartShown(r),
    'off': [
      for (final o in r.offSpans.where((o) => o[0] <= t))
        [
          activeMs(r, o[0].toInt()),
          (o[1] < 0 ? t : math.min(o[1].toInt(), t)) - o[0].toInt(),
          ((o[1] < 0 ? r.offM : o[3]) - o[2]).round(),
        ],
    ],
  };
}
