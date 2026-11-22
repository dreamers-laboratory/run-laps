// The oval you run, where it lies on the ground, and fitting a GPS path onto it.
import 'dart:math' as math;
import 'dart:typed_data';

/* ---------- a standard 400 m track (World Athletics), in metres ---------- */
const double straight = 84.39;
const double kerbRadius = 36.5;
const double laneWidth = 1.22;
const double trackWidth = 8 * laneWidth; // kerb to the outer edge of lane 8

/// Radius of the line a lane is measured on: 0.30 m out from the kerb in lane 1,
/// 0.20 m out from the inner lane line in every other lane.
double laneRadius(int lane) => lane <= 1 ? kerbRadius + 0.30 : kerbRadius + 0.20 + laneWidth * (lane - 1);

/// One lap of a lane: lane 1 = 400.00 m, lane 2 = 407.04 m, lane 4 = 422.37 m, lane 8 = 453.03 m.
double laneLength(int lane) => 2 * straight + 2 * math.pi * laneRadius(lane);

class Pt {
  final double x, y;
  const Pt(this.x, this.y);
  double dist(Pt o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));
  List<double> toJson() => [x, y];
  static Pt fromJson(List<dynamic> j) => Pt((j[0] as num).toDouble(), (j[1] as num).toDouble());
}

/// One lane of a track: two straights of st joined by half circles of radius r. u is the position
/// round it, 0..1, from the foot of the right straight, counter-clockwise (x right, y down; the
/// screen lays it on its side, so the right straight is the bottom one).
class Oval {
  final double r, st, perim;
  Oval(this.r, [this.st = straight]) : perim = 2 * st + 2 * math.pi * r;
  factory Oval.lane(int lane) => Oval(laneRadius(lane));
  double get h => st / 2;

  /// The finish line: the end of the home straight.
  double get uFinish => st / perim;
  bool get standard => (st - straight).abs() < 0.01;

  Pt along(double u) {
    var d = (((u % 1) + 1) % 1) * perim;
    if (d < st) return Pt(r, h - d);
    d -= st;
    if (d < math.pi * r) {
      final a = d / r;
      return Pt(r * math.cos(a), -h - r * math.sin(a));
    }
    d -= math.pi * r;
    if (d < st) return Pt(-r, -h + d);
    d -= st;
    final a = d / r;
    return Pt(-r * math.cos(a), h + r * math.sin(a));
  }

  /// The nearest point on the oval, as u.
  double uOf(double x, double y) {
    if (y <= -h) return (st + r * math.atan2(-(y + h), x)) / perim;
    if (y >= h) return (2 * st + math.pi * r + r * math.atan2(y - h, -x)) / perim;
    return x >= 0 ? (h - y) / perim : (st + math.pi * r + y + h) / perim;
  }

  /// How far a point is from the line: + outside, − inside.
  double sd(double x, double y) {
    final ay = y.abs();
    if (ay <= h) return x.abs() - r;
    final dy = ay - h;
    return math.sqrt(x * x + dy * dy) - r;
  }

  Pt normalAt(double u) {
    final a = along(u - 0.001), b = along(u + 0.001);
    final tx = b.x - a.x, ty = b.y - a.y, l = math.sqrt(tx * tx + ty * ty);
    return Pt(ty / l, -tx / l);
  }

  /// Which way u counts at u, as a unit vector.
  Pt tangentAt(double u) {
    final a = along(u - 0.0005), b = along(u + 0.0005), l = a.dist(b);
    return Pt((b.x - a.x) / l, (b.y - a.y) / l);
  }

  /// Radians of bend in the stretch that starts at u0 and runs len metres going dir.
  double turned(double u0, int dir, double len) {
    var n = 0;
    for (var m = 0.5; m < len; m += 1) {
      final d = ((((u0 * perim + dir * m) % perim) + perim) % perim);
      if ((d >= st && d < st + math.pi * r) || d >= 2 * st + math.pi * r) n++;
    }
    return n / r;
  }
}

/// Where an oval lies on the ground: local metres (east, north) into the oval's frame.
/// North flips to down, then it turns and shifts; the picture on screen is the ground turned, never mirrored.
class Geo {
  final double c, s, tx, ty;
  const Geo(this.c, this.s, this.tx, this.ty);

  /// The oval centred on (cx, cy) in local metres, turned by a.
  factory Geo.centred(double a, double cx, double cy) {
    final c = math.cos(a), s = math.sin(a);
    return Geo(c, s, -(c * cx + s * cy), -(s * cx - c * cy));
  }

  double get angle => math.atan2(s, c);
  Pt get centre => invert(const Pt(0, 0));
  Pt apply(Pt q) => Pt(c * q.x + s * q.y + tx, s * q.x - c * q.y + ty);
  Pt invert(Pt p) {
    final a = p.x - tx, b = p.y - ty;
    return Pt(c * a + s * b, s * a - c * b);
  }

  /// The same oval the other way up (an oval looks the same turned half round).
  Geo flipped() => Geo(-c, -s, -tx, -ty);
  List<double> toJson() => [c, s, tx, ty];
  static Geo fromJson(List<dynamic> j) =>
      Geo((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());
}

/// The turn and shift that best lay local points q onto oval-frame points m.
Geo kabsch(List<Pt> q, List<Pt> m, [List<double>? w]) {
  var sw = 0.0, ax = 0.0, ay = 0.0, bx = 0.0, by = 0.0;
  for (var i = 0; i < q.length; i++) {
    final wi = w == null ? 1.0 : w[i];
    sw += wi;
    ax += wi * q[i].x;
    ay -= wi * q[i].y;
    bx += wi * m[i].x;
    by += wi * m[i].y;
  }
  ax /= sw;
  ay /= sw;
  bx /= sw;
  by /= sw;
  var a = 0.0, b = 0.0;
  for (var i = 0; i < q.length; i++) {
    final wi = w == null ? 1.0 : w[i];
    final fx = q[i].x - ax, fy = -q[i].y - ay, mx = m[i].x - bx, my = m[i].y - by;
    a += wi * (fx * mx + fy * my);
    b += wi * (fx * my - fy * mx);
  }
  final th = math.atan2(b, a), c = math.cos(th), s = math.sin(th);
  return Geo(c, s, bx - (c * ax - s * ay), by - (s * ax + c * ay));
}

/// Settle the fit: lay each point on its nearest spot of the oval, refit, repeat. Far points count less.
Geo icp(List<Pt> q, Oval o, Geo g, {int iters = 8, double k = 6}) {
  for (var it = 0; it < iters; it++) {
    final m = <Pt>[], w = <double>[];
    for (final p in q) {
      final e = g.apply(p), c = o.along(o.uOf(e.x, e.y)), d = e.dist(c);
      m.add(c);
      w.add(d <= k ? 1 : k / d);
    }
    g = kabsch(q, m, w);
  }
  return g;
}

/// How far the points sit from the oval: root mean square of the closest 90%.
double fitRms(List<Pt> q, Oval o, Geo g) {
  final d = [
    for (final p in q)
      () {
        final e = g.apply(p), v = o.sd(e.x, e.y);
        return v * v;
      }(),
  ]..sort();
  final n = math.max(1, (d.length * 0.9).floor());
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    s += d[i];
  }
  return math.sqrt(s / n);
}

/// Your path laid onto a track: which way you run, where you are, and how sure.
class Reg {
  final Oval oval;
  final Geo geo;
  final int dir; // 1 counter-clockwise, -1 clockwise
  final double scale, rms, altDir, altPhase, turned, worst; // turned: radians of bend; worst: farthest point off (m)
  Reg(this.oval, this.geo, this.dir, this.scale, this.rms, this.altDir, this.altPhase, this.turned, this.worst);
}

const _scales = [0.6, 0.75, 0.9, 1.0, 1.15, 1.35];

/// Lay the path (points with the distance run to each) onto the track base, at every place round
/// it, both ways, and a few track sizes. A path that is only straight fits anywhere on a straight:
/// the bend is what pins it down.
Reg? register(List<Pt> pts, List<double> s, Oval base, {List<double> scales = _scales}) {
  final n = pts.length;
  if (n < 8) return null;
  final ax = Float64List(n), ay = Float64List(n);
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < n; i++) {
    ax[i] = pts[i].x;
    ay[i] = -pts[i].y;
    cx += ax[i];
    cy += ay[i];
  }
  cx /= n;
  cy /= n;
  var pp = 0.0;
  for (var i = 0; i < n; i++) {
    ax[i] -= cx;
    ay[i] -= cy;
    pp += ax[i] * ax[i] + ay[i] * ay[i];
  }
  // per scale and direction: the fit at every 2 m round half the oval (the other half is the same oval turned)
  final fits = <(double, int, List<double>, int, double)>[]; // scale, dir, rms by place, step, metres per step
  ({double f, int dir, int k, double rms})? best, best1;
  for (final f in scales) {
    final o = Oval(base.r * f, base.st * f);
    final m = (o.perim / 0.5).floor();
    final tx = Float64List(m), ty = Float64List(m);
    for (var k = 0; k < m; k++) {
      final p = o.along(k / m);
      tx[k] = p.x;
      ty[k] = p.y;
    }
    final perK = m / o.perim;
    final idx = Float64List(n);
    for (var i = 0; i < n; i++) {
      idx[i] = (s[i] - s[0]) * perK;
    }
    final step = math.max(1, (2 * perK).round());
    for (final dir in const [1, -1]) {
      final arr = <double>[];
      for (var k0 = 0; k0 < m ~/ 2; k0 += step) {
        var sx = 0.0, sy = 0.0, mm = 0.0, a = 0.0, b = 0.0;
        for (var i = 0; i < n; i++) {
          final k = (k0 + dir * idx[i]).round() % m;
          final mx = tx[k], my = ty[k];
          sx += mx;
          sy += my;
          mm += mx * mx + my * my;
          a += ax[i] * mx + ay[i] * my;
          b += ax[i] * my - ay[i] * mx;
        }
        final r2 = pp + mm - (sx * sx + sy * sy) / n - 2 * math.sqrt(a * a + b * b);
        final rms = math.sqrt(math.max(0, r2) / n);
        arr.add(rms);
        if (best == null || rms < best.rms) best = (f: f, dir: dir, k: k0, rms: rms);
        if (f == 1.0 && (best1 == null || rms < best1.rms)) best1 = (f: f, dir: dir, k: k0, rms: rms);
      }
      fits.add((f, dir, arr, step, step / perK));
    }
  }
  if (best == null) return null;
  // a standard track unless another size fits clearly better
  final pick = (best1 != null && best.rms > 0.7 * best1.rms) ? best1 : best;
  final o = Oval(base.r * pick.f, base.st * pick.f);
  var altDir = double.infinity, altPhase = double.infinity;
  for (final (f, dir, arr, step, mPer) in fits) {
    if (f != pick.f) continue;
    if (dir != pick.dir) {
      for (final v in arr) {
        altDir = math.min(altDir, v);
      }
      continue;
    }
    final at = pick.k ~/ step;
    for (var j = 0; j < arr.length; j++) {
      final gap = (j - at).abs() * mPer, circ = math.min(gap, o.perim / 2 - gap);
      if (circ > 12) altPhase = math.min(altPhase, arr[j]);
    }
  }
  // the matched points, then settle the fit onto the oval itself
  final m = (o.perim / 0.5).floor();
  final model = <Pt>[];
  for (var i = 0; i < n; i++) {
    final k = (pick.k + pick.dir * (s[i] - s[0]) * m / o.perim).round() % m;
    model.add(o.along(k / m));
  }
  var g = kabsch(pts, model);
  g = icp(pts, o, g);
  final u0 = o.uOf(g.apply(pts.first).x, g.apply(pts.first).y);
  var worst = 0.0;
  for (final p in pts) {
    final e = g.apply(p);
    worst = math.max(worst, o.sd(e.x, e.y).abs());
  }
  return Reg(
    o,
    g,
    pick.dir,
    pick.f,
    fitRms(pts, o, g),
    altDir,
    altPhase,
    o.turned(u0, pick.dir, s[n - 1] - s[0]),
    worst,
  );
}

/// The smallest of a function, by the Nelder–Mead simplex.
List<double> nelderMead(double Function(List<double>) f, List<double> x0, List<double> step, {int iters = 400}) {
  final n = x0.length;
  var pts = <List<double>>[
    [...x0],
    for (var i = 0; i < n; i++) [for (var j = 0; j < n; j++) x0[j] + (i == j ? step[j] : 0)],
  ];
  var vals = [for (final p in pts) f(p)];
  for (var it = 0; it < iters; it++) {
    final order = List.generate(n + 1, (i) => i)..sort((a, b) => vals[a].compareTo(vals[b]));
    pts = [for (final i in order) pts[i]];
    vals = [for (final i in order) vals[i]];
    final c = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        c[j] += pts[i][j] / n;
      }
    }
    List<double> toward(double t) => [for (var j = 0; j < n; j++) c[j] + t * (pts[n][j] - c[j])];
    final xr = toward(-1), fr = f(xr);
    if (fr < vals[0]) {
      final xe = toward(-2), fe = f(xe);
      pts[n] = fe < fr ? xe : xr;
      vals[n] = math.min(fe, fr);
    } else if (fr < vals[n - 1]) {
      pts[n] = xr;
      vals[n] = fr;
    } else {
      final xc = fr < vals[n] ? toward(-0.5) : toward(0.5), fc = f(xc);
      if (fc < math.min(fr, vals[n])) {
        pts[n] = xc;
        vals[n] = fc;
      } else {
        for (var i = 1; i <= n; i++) {
          pts[i] = [for (var j = 0; j < n; j++) pts[0][j] + 0.5 * (pts[i][j] - pts[0][j])];
          vals[i] = f(pts[i]);
        }
      }
    }
  }
  var b = 0;
  for (var i = 1; i <= n; i++) {
    if (vals[i] < vals[b]) b = i;
  }
  return pts[b];
}

/// A whole lap or more of path, fitted to an oval of any size: where it is, its straight and its radius.
({Geo geo, Oval oval, double rms})? fitShape(List<Pt> q, Geo g0, Oval o0) {
  if (q.length < 20) return null;
  final c0 = g0.centre;
  double cost(List<double> v) {
    if (v[3] < 12 || v[3] > 90 || v[4] < 0 || v[4] > 240) return 1e18;
    final g = Geo.centred(v[0], v[1], v[2]), o = Oval(v[3], v[4]);
    var sum = 0.0;
    for (final p in q) {
      final e = g.apply(p), d = o.sd(e.x, e.y).abs();
      sum += d <= 6 ? d * d : 12 * d - 36;
    }
    return sum / q.length;
  }

  final v = nelderMead(cost, [g0.angle, c0.x, c0.y, o0.r, o0.st], [0.08, 5, 5, 3, 12], iters: 500);
  final g = Geo.centred(v[0], v[1], v[2]), o = Oval(v[3], v[4]);
  return (geo: g, oval: o, rms: fitRms(q, o, g));
}

/// The centre of the points and the direction of their long axis.
({double x, double y, double angle}) longAxis(List<Pt> q) {
  var cx = 0.0, cy = 0.0;
  for (final p in q) {
    cx += p.x;
    cy += p.y;
  }
  cx /= q.length;
  cy /= q.length;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in q) {
    sxx += (p.x - cx) * (p.x - cx);
    syy += (p.y - cy) * (p.y - cy);
    sxy += (p.x - cx) * (p.y - cy);
  }
  return (x: cx, y: cy, angle: 0.5 * math.atan2(2 * sxy, sxx - syy));
}

/// The direction a loop goes, from its area: 1 counter-clockwise on the ground, -1 clockwise.
int loopDir(List<Pt> q) {
  var a = 0.0;
  for (var i = 1; i < q.length; i++) {
    a += q[i - 1].x * q[i].y - q[i].x * q[i - 1].y;
  }
  return a >= 0 ? 1 : -1;
}
