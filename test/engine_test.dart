import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:laps/engine.dart';

import 'sim.dart';

/// A runner on the measured line of a lane, from the finish line, with GPS-like noise.
class Sim {
  final int lane;
  final double acc;
  final Oval oval;
  final OnTrack track;
  final Gnss gnss;
  final math.Random rnd;
  Sim(this.lane, {double sigma = 2, double drift = 0, this.acc = 5, double rot = 0.4, int seed = 1})
    : oval = Oval.lane(lane),
      track = OnTrack(Oval.lane(lane), Geo.centred(rot, 0, 0), Oval.lane(lane).uFinish, 1),
      gnss = Gnss(seed, sigma: sigma, drift: drift),
      rnd = math.Random(seed + 1000);
  Fix fix(double pos, int t, {double? spd}) => fixAt(gnss.noisy(track.at(pos), 1), t, acc: acc, spd: spd);
}

/// Run [laps] laps (plus a bit) and report counted laps and the worst lap-time error.
({int counted, int truth, double worst}) runLaps(Sim sim, int laps, {int gapSecs = 0}) {
  final r = Run(sim.lane, 0);
  final L = sim.oval.perim;
  var pos = 0.0, t = 0;
  final truth = <double>[];
  var next = L;
  while (truth.length < laps) {
    final v = 3.3 + 0.6 * math.sin(t / 60000) + (sim.rnd.nextDouble() - 0.5) * 0.4;
    final before = pos;
    pos += v;
    t += 1000;
    if (pos >= next) {
      truth.add(t - 1000 + 1000 * (next - before) / v);
      next += L;
    }
    final inLap = pos % L;
    if (gapSecs > 0 && t > 20000 && (inLap < gapSecs * 3.3 || L - inLap < gapSecs * 3.3 / 2)) continue;
    feed(r, sim.fix(pos, t, spd: v));
  }
  for (var i = 0; i < 40; i++) {
    pos += 3.4;
    t += 1000;
    feed(r, sim.fix(pos, t, spd: 3.4));
  }
  var worst = 0.0;
  for (var i = 0; i < truth.length && i < r.laps.length; i++) {
    worst = math.max(worst, (r.laps[i] - truth[i]).abs() / 1000);
  }
  return (counted: r.laps.length, truth: truth.length, worst: worst);
}

void main() {
  group('lanes', () {
    test('lap length per lane matches the 400 m stagger', () {
      expect(laneLength(1), closeTo(400.00, 0.01));
      expect(laneLength(2), closeTo(407.04, 0.01));
      expect(laneLength(3), closeTo(414.70, 0.01));
      expect(laneLength(4), closeTo(422.37, 0.01));
      expect(laneLength(8), closeTo(453.03, 0.01));
    });
    test('4 laps: less than a mile in lane 1, more in lane 2', () {
      expect(4 * laneLength(1), lessThan(mile));
      expect(mile - 4 * laneLength(1), closeTo(9.34, 0.01));
      expect(4 * laneLength(2), greaterThan(mile));
    });
    test('the drawn oval of a lane is that lane, to the centimetre', () {
      for (var lane = 1; lane <= 8; lane++) {
        final o = Oval.lane(lane);
        var len = 0.0;
        var prev = o.along(0);
        for (var i = 1; i <= 4000; i++) {
          final p = o.along(i / 4000);
          len += p.dist(prev);
          prev = p;
        }
        expect(len, closeTo(laneLength(lane), 0.05), reason: 'lane $lane');
      }
    });
    test('uOf finds the nearest point back', () {
      final o = Oval.lane(4);
      for (var i = 0; i < 100; i++) {
        final u = i / 100, p = o.along(u), n = o.normalAt(u);
        final back = o.uOf(p.x + n.x * 2, p.y + n.y * 2);
        expect(((back - u + 1.5) % 1) - 0.5, closeTo(0, 0.002), reason: 'u=$u');
      }
    });
  });

  group('lap counting under GPS noise', () {
    final cases = <(String, int, double, double, double, int)>[
      // name, lane, white sigma, drift, reported accuracy, laps
      ('clean lane 1', 1, 1, 0, 5, 10),
      ('white 4 m lane 1', 1, 4, 0, 8, 10),
      ('white 6 m lane 2', 2, 6, 0, 12, 8),
      ('drift 5 m lane 4', 4, 1, 5, 6, 10),
      ('lane 8', 8, 2, 2, 6, 8),
    ];
    for (final (name, lane, sigma, drift, acc, laps) in cases) {
      test('$name: every lap, 40 runs', () {
        final errs = <double>[];
        for (var seed = 1; seed <= 40; seed++) {
          final res = runLaps(Sim(lane, sigma: sigma, drift: drift, acc: acc, seed: seed, rot: seed * 0.37), laps);
          expect(res.counted, res.truth, reason: '$name seed $seed');
          errs.add(res.worst);
        }
        errs.sort();
        final p95 = errs[(errs.length * 0.95).floor() - 1];
        expect(p95, lessThan(sigma >= 6 || drift >= 5 ? 6.5 : 4.5), reason: '$name p95 worst-lap error $p95 s');
      });
    }
    test('a 14 s GPS gap at the start line still counts every lap', () {
      for (var seed = 1; seed <= 10; seed++) {
        final res = runLaps(Sim(2, sigma: 2, drift: 2, acc: 6, seed: seed), 8, gapSecs: 14);
        expect(res.counted, res.truth, reason: 'seed $seed');
      }
    });
    test('standing still for 15 minutes counts nothing', () {
      final sim = Sim(1, sigma: 3, drift: 3, acc: 6, seed: 3);
      final r = Run(1, 0);
      for (var t = 0; t < 900000; t += 1000) {
        feed(r, sim.fix(0, t));
      }
      expect(r.laps, isEmpty);
    });
    test('standing still with the chip saying 0 m/s adds no distance', () {
      final sim = Sim(1, sigma: 3, drift: 3, acc: 6, seed: 4);
      final r = Run(1, 0);
      for (var t = 0; t < 300000; t += 1000) {
        feed(r, sim.fix(0, t, spd: 0.1));
      }
      expect(r.since, 0);
    });
  });

  group('GPS jumps', () {
    // A GPS simulator, or a stale first fix: the first position is one place, every one after it
    // another place 2 km off, where the phone barely moves.
    ({int laps, double metres, double? mph}) jumpThenStill(int lane, {int seed = 1, bool interleave = false}) {
      final g = Gnss(seed, sigma: 2, drift: 1), r = Run(lane, 0);
      feed(r, fixAt(const Pt(0, 0), 0, acc: 8));
      var t = 0;
      for (var i = 0; i < 120; i++) {
        t += 1000;
        final there = Pt(1700 + i * 0.3, 1200); // 2.08 km away, drifting 0.3 m/s
        feed(r, fixAt(interleave && i.isOdd ? g.noisy(const Pt(0, 0), 1) : g.noisy(there, 1), t, acc: 8));
      }
      final s = stats(r, t, fracs(r));
      return (laps: r.laps.length, metres: s.metres, mph: s.mph);
    }

    for (final lane in [1, 4, 8]) {
      test('a jump of 2 km after the first fix is not run: lane $lane, 10 seeds', () {
        for (var seed = 1; seed <= 10; seed++) {
          final res = jumpThenStill(lane, seed: seed);
          expect(res.laps, 0, reason: 'seed $seed');
          expect(res.metres, lessThan(150), reason: 'seed $seed');
          expect(res.mph ?? 0, lessThan(3), reason: 'seed $seed');
        }
      });
    }
    test('fixes flipping between two places 2 km apart count nothing', () {
      for (var seed = 1; seed <= 10; seed++) {
        final res = jumpThenStill(8, seed: seed, interleave: true);
        expect(res.laps, 0, reason: 'seed $seed');
        expect(res.metres, lessThan(150), reason: 'seed $seed');
      }
    });
    test('no lap is ever quicker than a world record', () {
      final sim = Sim(2, seed: 5), r = Run(2, 0);
      var pos = 0.0, t = 0;
      for (var i = 0; i < 400; i++) {
        pos += 3.4;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: 3.4));
      }
      // then 3 km away in an instant, and still
      for (var i = 0; i < 60; i++) {
        t += 1000;
        feed(r, fixAt(Pt(3000, 0 + i * 0.2), t, acc: 6));
      }
      final laps = [0, ...r.laps];
      for (var i = 1; i < laps.length; i++) {
        expect(laps[i] - laps[i - 1], greaterThan(r.L / 9 * 1000), reason: 'lap $i');
      }
      expect(r.laps.length, lessThanOrEqualTo((400 * 3.4 / r.L).floor()));
    });
  });

  group('stops', () {
    test('stopped time is not running time, laps after the press do not count', () {
      final sim = Sim(1, seed: 7);
      final r = Run(1, 0);
      var pos = 0.0, t = 0;
      while (r.laps.length < 2) {
        pos += 3.5;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: 3.5));
      }
      final stopT = t + 5000;
      for (var i = 0; i < 5; i++) {
        pos += 3.5;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: 3.5));
      }
      stopAt(r, stopT);
      resumeRun(r, stopT, stopT + 90000);
      t = stopT + 90000;
      expect(activeMs(r, t), stopT);
      expect(activeMs(r, t + 1000), stopT + 1000);
      while (r.laps.length < 4) {
        pos += 3.5;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: 3.5));
      }
      final e = historyEntry(r, t, null, 'half marathon');
      expect((e['laps'] as List).length, 4);
      expect((e['pauses'] as List).single, [stopT, 90000]);
      expect(r.trace.where((q) => q == null).length, 1);
      // lap 3 ran through the stop: its split leaves the 90 s out
      final split3 = (e['laps'] as List)[2] as int;
      expect(split3, lessThan(400 / 3.5 * 1000 + 8000));
    });
  });

  group('top speed', () {
    test('a sprint shows; a one-fix spike does not', () {
      final sim = Sim(1, sigma: 1.5, seed: 9);
      final r = Run(1, 0);
      var pos = 0.0, t = 0;
      void go(double v, int secs) {
        for (var i = 0; i < secs; i++) {
          pos += v;
          t += 1000;
          feed(r, sim.fix(pos, t, spd: v));
        }
      }

      go(3.5, 60);
      go(8.5, 10); // 19.0 mph
      go(3.5, 30);
      pos += 3.5;
      t += 1000;
      feed(r, sim.fix(pos, t, spd: 11)); // one bad Doppler reading
      go(3.5, 20);
      expect(r.top * mpsToMph, closeTo(8.5 * mpsToMph, 0.2));
      expect(stats(r, t, Frac.zero).topMph, closeTo(19.0, 0.2));
    });
    test('without Doppler it falls back to movement, near the true speed', () {
      final sim = Sim(1, sigma: 0.8, seed: 10);
      final r = Run(1, 0);
      var pos = 0.0, t = 0;
      for (var i = 0; i < 120; i++) {
        pos += 4.0;
        t += 1000;
        feed(r, sim.fix(pos, t));
      }
      expect(r.top, inInclusiveRange(3.6, 5.2));
    });
    test('each lap keeps its own top speed', () {
      final sim = Sim(1, sigma: 1, seed: 11);
      final r = Run(1, 0);
      var pos = 0.0, t = 0;
      var lapV = 3.4;
      while (r.laps.length < 3) {
        final before = r.laps.length;
        pos += lapV;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: lapV));
        if (r.laps.length != before) lapV = r.laps.length == 1 ? 6.0 : 3.4;
      }
      expect(r.lapTop.length, 3);
      expect(r.lapTop[1], greaterThan(r.lapTop[0] + 1.5));
    });
  });

  test('standing still mid-run does not skew the drawing', () {
    final sim = Sim(4, sigma: 2, seed: 21, rot: 1.1);
    final r = Run(4, 0);
    var pos = 0.0, t = 0;
    void go(int secs, double v, {double? spd}) {
      for (var i = 0; i < secs; i++) {
        pos += v;
        t += 1000;
        feed(r, sim.fix(pos, t, spd: spd ?? v));
      }
    }

    go(300, 3.5);
    go(240, 0, spd: 0.1); // four minutes stood still, chip says so
    go(240, 0, spd: null); // four more with no speed from the chip (jitter only)
    go(300, 3.5);
    final oval = r.oval, f = r.geo!;
    final ds = [
      for (final q in r.trace.whereType<Pt>())
        () {
          final p = f.apply(q);
          return oval.sd(p.x, p.y).abs();
        }(),
    ]..sort();
    expect(r.sense, 'refined');
    expect(ds[ds.length ~/ 2], lessThan(2.5), reason: 'median off the oval');
  });

  test('a run survives being saved and restored', () {
    final sim = Sim(4, seed: 12);
    final r = Run(4, 1000);
    var pos = 0.0, t = 1000;
    for (var i = 0; i < 200; i++) {
      pos += 3.6;
      t += 1000;
      feed(r, sim.fix(pos, t, spd: 3.6));
    }
    final back = Run.fromJson(r.toJson());
    expect(back.lane, 4);
    expect(back.L, closeTo(422.37, 0.01));
    expect(back.laps, r.laps);
    expect(back.trace.whereType<Pt>().length, r.trace.whereType<Pt>().length);
    expect(back.top, r.top);
  });
}
