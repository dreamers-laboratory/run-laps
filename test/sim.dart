// A pretend runner and a pretend GPS chip, for the simulations.
import 'dart:math' as math;

import 'package:laps/engine.dart';

const _earth = 6371008.8, _k = math.pi / 180;
const lat0 = 45.0, lon0 = 10.0; // anywhere will do

/// GPS error: white noise per fix plus a slow wander (what a phone's error really looks like).
class Gnss {
  final math.Random rnd;
  final double sigma, drift, tau, spikes; // m, m, s, chance of a 20 m bad fix
  double bx = 0, by = 0;
  Gnss(int seed, {this.sigma = 2, this.drift = 0, this.tau = 60, this.spikes = 0}) : rnd = math.Random(seed);
  double g() => math.sqrt(-2 * math.log(rnd.nextDouble() + 1e-12)) * math.cos(2 * math.pi * rnd.nextDouble());
  Pt noisy(Pt q, double dt) {
    final a = math.exp(-dt / tau), w = math.sqrt(1 - a * a);
    bx = bx * a + g() * drift * w;
    by = by * a + g() * drift * w;
    var x = q.x + bx + g() * sigma, y = q.y + by + g() * sigma;
    if (spikes > 0 && rnd.nextDouble() < spikes) {
      final th = rnd.nextDouble() * 2 * math.pi;
      x += 20 * math.cos(th);
      y += 20 * math.sin(th);
    }
    return Pt(x, y);
  }
}

Fix fixAt(Pt q, int t, {double acc = 6, double? spd}) =>
    Fix(lat0 + q.y / _earth / _k, lon0 + q.x / (_earth * math.cos(lat0 * _k)) / _k, acc, t, spd: spd);

/// Where the runner is after m metres, in ground metres east/north.
abstract class Course {
  Pt at(double m);
}

/// Round a lane of a track: oval o lying as truth says, from u0, going dir.
class OnTrack implements Course {
  final Oval o;
  final Geo truth;
  final double u0;
  final int dir;
  OnTrack(this.o, this.truth, this.u0, this.dir);
  @override
  Pt at(double m) => truth.invert(o.along(u0 + dir * m / o.perim));
  Pt get startPt => at(0);
}

/// Straight pieces through the given points, then standing at the last.
class Polyline implements Course {
  final List<Pt> p;
  final List<double> s = [0];
  Polyline(this.p) {
    for (var i = 1; i < p.length; i++) {
      s.add(s.last + p[i].dist(p[i - 1]));
    }
  }
  double get length => s.last;
  @override
  Pt at(double m) {
    if (m <= 0) return p.first;
    for (var i = 1; i < p.length; i++) {
      if (m <= s[i]) {
        final f = (m - s[i - 1]) / (s[i] - s[i - 1]);
        return Pt(p[i - 1].x + f * (p[i].x - p[i - 1].x), p[i - 1].y + f * (p[i].y - p[i - 1].y));
      }
    }
    return p.last;
  }
}

/// One course, then the next from where the first left off (each piece is [course, metres]).
class Joined implements Course {
  final List<(Course, double)> parts;
  Joined(this.parts);
  @override
  Pt at(double m) {
    for (final (c, len) in parts) {
      if (m <= len) return c.at(m);
      m -= len;
    }
    final (c, len) = parts.last;
    return c.at(len + m);
  }
}

class Out {
  final Run r;
  final double metres; // true distance run
  final int t;
  double? sensedM; // true metres run when the track was first sensed
  final List<(double, bool)> offAt = []; // (true metres, off?) at each change
  Out(this.r, this.metres, this.t);
}

/// Run a course for metres (true distance), one fix a second, the chip's Doppler speed included.
Out runCourse(
  Course c,
  double metres, {
  int seed = 1,
  double sigma = 2,
  double drift = 0,
  double spikes = 0,
  double acc = 6,
  int lane = 1,
  int dir = 1,
  List<Map<String, dynamic>> tracks = const [],
  double Function(double m, int t)? speed,
  Run? run,
  void Function(Run r)? onSense,
  double gapEvery = 0, // a GPS dropout every this many metres
  int gapSecs = 0,
}) {
  final r = run ?? Run(lane, 0, dir: dir, tracks: tracks);
  final gn = Gnss(seed, sigma: sigma, drift: drift, spikes: spikes);
  final rnd = math.Random(seed * 7 + 1);
  var m = 0.0, t = 0;
  final o = Out(r, 0, 0);
  var sense = r.sense, off = r.off;
  while (m < metres) {
    final v = speed?.call(m, t) ?? 3.3 + 0.4 * math.sin(t / 50000) + (rnd.nextDouble() - 0.5) * 0.3;
    m += v;
    t += 1000;
    final q = gn.noisy(c.at(m), 1);
    if (gapEvery > 0 && m % gapEvery < v * gapSecs) continue; // no fix: under the stands, in a tunnel
    feed(r, fixAt(q, t, acc: acc, spd: v));
    if (r.sense != sense) {
      if (sense == 'default' || sense == 'saved') {
        o.sensedM ??= m;
        onSense?.call(r);
      }
      sense = r.sense;
    }
    if (r.off != off) {
      o.offAt.add((m, r.off));
      off = r.off;
    }
  }
  return Out(r, m, t)
    ..sensedM = o.sensedM
    ..offAt.addAll(o.offAt);
}

/// A point of the run's own frame (metres from its first fix) on the simulation's ground.
Pt groundOf(Run r, Pt q) {
  final lat = r.ref!['lat']! + q.y / _earth / _k,
      lon = r.ref!['lon']! + q.x / (_earth * math.cos(r.ref!['lat']! * _k)) / _k;
  return Pt((lon - lon0) * _k * _earth * math.cos(lat0 * _k), (lat - lat0) * _k * _earth);
}

/// How far the sensed oval sits from the real one, on average (m).
double overlayErr(Run r, Oval truthOval, Geo truth) {
  if (r.geo == null) return double.infinity;
  var s = 0.0;
  for (var k = 0; k < 100; k++) {
    final g = groundOf(r, r.geo!.invert(r.oval.along(k / 100))), e = truth.apply(g);
    s += truthOval.sd(e.x, e.y).abs();
  }
  return s / 100;
}

/// How far the drawn start is from where the runner really started (m).
double startErr(Run r, Pt truthStart) {
  if (r.geo == null || r.uStart == null) return double.infinity;
  return groundOf(r, r.geo!.invert(r.oval.along(r.uStart!))).dist(truthStart);
}

/// The unit normal at u pointing out of the oval.
Pt outward(Oval o, double u) {
  final n = o.normalAt(u), a = o.along(u);
  return o.sd(a.x + n.x, a.y + n.y) > 0 ? n : Pt(-n.x, -n.y);
}

double pct(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[math.min(s.length - 1, (s.length * p).floor())];
}
