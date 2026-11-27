// Simulated runs for the track: sensing its shape, direction and start; tracks kept between runs;
// running off it. Each case runs many seeds of a pretend GPS chip (white noise plus slow wander).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:laps/engine.dart';

import 'sim.dart';

Geo truthFor(int seed) => Geo.centred(seed * 0.71, 30.0 * math.sin(seed.toDouble()), 20.0 * math.cos(seed * 1.3));

String offs(Out o) => o.offAt.map((x) => '${x.$2 ? 'off' : 'on'}@${x.$1.round()}').join(' ');

double metresOf(Out o) => stats(o.r, o.t, fracs(o.r)).metres;

void main() {
  final summary = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('\n${summary.join('\n')}');
  });

  group('sensing a standard track', () {
    final cases = <(String, int, int, double, bool)>[
      // name, lane, true direction, start in metres past the finish line, default already right
      ('finish line, counter-clockwise, lane 1', 1, 1, 0, true),
      ('end of the home straight, ccw, lane 1', 1, 1, 390, true),
      ('middle of the back straight, ccw, lane 2', 2, 1, 115.6 + 42, false),
      ('middle of a bend, ccw, lane 4', 4, 1, 60, false),
      ('finish line, clockwise, lane 2', 2, -1, 0, false),
      ('middle of a straight, clockwise, lane 8', 8, -1, 242, false),
    ];
    const noise = [(2.0, 0.0, 'clean'), (3.0, 3.0, 'typical'), (6.0, 0.0, 'rough')];
    for (final (name, lane, dir, s0, defaultRight) in cases) {
      for (final (sg, dr, nn) in noise) {
        test('$name, $nn GPS: 20 runs', () {
          final sensedAt = <double>[], startE = <double>[], overlay = <double>[];
          var wrongDir = 0, falseOff = 0, notes = 0, lapsOk = 0;
          for (var seed = 1; seed <= 20; seed++) {
            final o = Oval.lane(lane), truth = truthFor(seed);
            final c = OnTrack(o, truth, o.uFinish + s0 / o.perim, dir);
            final out = runCourse(c, 3 * o.perim + 150, seed: seed, sigma: sg, drift: dr, acc: 4 + sg, lane: lane);
            final r = out.r;
            if (out.sensedM != null) sensedAt.add(out.sensedM!);
            if (r.dir != dir) wrongDir++;
            startE.add(startErr(r, c.startPt));
            overlay.add(overlayErr(r, o, truth));
            if (out.offAt.isNotEmpty) falseOff++;
            if (r.sensedAt != null) notes++;
            if (r.laps.length == 3) lapsOk++;
          }
          summary.add(
            '${'$name, $nn'.padRight(56)} sensed after ${pct(sensedAt, .5).round()} m (p95 ${pct(sensedAt, .95).round()}), '
            'start off by ${pct(startE, .5).toStringAsFixed(1)} m (p95 ${pct(startE, .95).toStringAsFixed(1)}), '
            'track p95 ${pct(overlay, .95).toStringAsFixed(1)} m, laps right $lapsOk/20, wrong way $wrongDir, false off $falseOff, note $notes/20',
          );
          expect(sensedAt.length, 20, reason: 'every run senses the track');
          expect(wrongDir, 0);
          expect(falseOff, 0, reason: 'never off the reservation on the track');
          // the start is your first fix as it came: rough GPS puts it up to 15 m out on its own
          expect(pct(startE, .95), lessThan(nn == 'rough' ? 18 : 10));
          expect(pct(overlay, .95), lessThan(6));
          expect(lapsOk, 20, reason: 'every lap counted');
          if (!defaultRight) expect(notes, 20, reason: 'the note shows when the drawing changes');
          if (defaultRight && nn == 'clean') expect(notes, 0, reason: 'no note when the guess was right');
        });
      }
    }
  });

  test('a 300 m track: its size is sensed, distance comes out right', () {
    final errL = <double>[], errM = <double>[];
    for (var seed = 1; seed <= 15; seed++) {
      final o3 = Oval(31.83, 50), truth = truthFor(seed);
      final c = OnTrack(o3, truth, o3.uFinish + 30 / o3.perim, 1);
      final out = runCourse(c, 4 * o3.perim + 150, seed: seed, sigma: 3, drift: 3, acc: 7);
      expect(out.r.oval.standard, isFalse, reason: 'seed $seed');
      expect(out.r.sensedAt, isNotNull);
      expect(out.offAt, isEmpty);
      errL.add((out.r.L - o3.perim).abs() / o3.perim);
      errM.add((metresOf(out) - out.metres).abs() / out.metres);
    }
    summary.add(
      '300 m track: lap length off by ${(pct(errL, .5) * 100).toStringAsFixed(1)}% (p95 ${(pct(errL, .95) * 100).toStringAsFixed(1)}%), distance off by ${(pct(errM, .5) * 100).toStringAsFixed(1)}% (p95 ${(pct(errM, .95) * 100).toStringAsFixed(1)}%)',
    );
    expect(pct(errL, .95), lessThan(0.04));
    expect(pct(errM, .95), lessThan(0.04));
  });

  group('a track kept from last time', () {
    test('known at the first fix; running it the other way flips the drawing', () {
      for (var seed = 1; seed <= 12; seed++) {
        final o = Oval.lane(1), truth = truthFor(seed);
        final first = runCourse(OnTrack(o, truth, o.uFinish, 1), 2 * o.perim, seed: seed, sigma: 3, drift: 3, acc: 7);
        final saved = trackOf(first.r, 1)!;
        expect(saved['dir'], 1);
        final c2 = OnTrack(o, truth, o.uFinish + 200 / o.perim, -1);
        final r2 = Run(1, 0, tracks: [saved]);
        feed(r2, fixAt(c2.startPt, 0, acc: 5, spd: 0));
        expect(r2.sense, 'saved', reason: 'the first fix finds it');
        expect(startErr(r2, c2.startPt), lessThan(8));
        final out = runCourse(c2, 3 * o.perim + 150, seed: seed + 100, sigma: 3, drift: 3, acc: 7, run: r2);
        expect(out.r.dir, -1, reason: 'seed $seed');
        expect(out.r.sensedAt, isNotNull, reason: 'the note shows');
        expect(out.r.laps.length, 3);
        expect(out.offAt, isEmpty);
      }
    });
    test('a different place: the kept track is not used', () {
      final o = Oval.lane(1), truth = truthFor(3);
      final first = runCourse(OnTrack(o, truth, o.uFinish, 1), 2 * o.perim, seed: 3, sigma: 2, acc: 6);
      final saved = trackOf(first.r, 1)!..['lat'] = (first.r.ref!['lat']! + 0.01); // 1.1 km north
      final out = runCourse(OnTrack(o, truth, o.uFinish, 1), 2 * o.perim, seed: 4, sigma: 2, acc: 6, tracks: [saved]);
      expect(out.r.sense, 'refined');
      expect(out.r.laps.length, 1);
    });
    test('started in the car park: laps count from where you join the track', () {
      final errM = <double>[];
      for (var seed = 1; seed <= 12; seed++) {
        final o = Oval.lane(1), truth = truthFor(seed);
        final track = OnTrack(o, truth, o.uFinish, 1);
        final saved = trackOf(runCourse(track, 2 * o.perim, seed: seed, sigma: 3, drift: 3, acc: 7).r, 1)!;
        final uJ = o.uFinish + 150 / o.perim, join = track.at(150), e = truth.apply(join), n = outward(o, uJ);
        final car = truth.invert(Pt(e.x + n.x * 70, e.y + n.y * 70));
        final c = Joined([
          (Polyline([car, join]), 70),
          (OnTrack(o, truth, uJ, 1), 3 * o.perim + 100),
        ]);
        final out = runCourse(c, 70 + 3 * o.perim + 100, seed: seed + 200, sigma: 3, drift: 3, acc: 7, tracks: [saved]);
        expect(out.r.anchored, isTrue);
        expect(out.r.laps.length, inInclusiveRange(2, 3), reason: 'seed $seed ${offs(out)}');
        errM.add((metresOf(out) - out.metres).abs() / out.metres);
      }
      summary.add(
        'car park start, 70 m to the track then 3 laps: distance off by ${(pct(errM, .5) * 100).toStringAsFixed(1)}% (p95 ${(pct(errM, .95) * 100).toStringAsFixed(1)}%)',
      );
      expect(pct(errM, .95), lessThan(0.03));
    });
  });

  group('off the reservation', () {
    for (final (sg, dr, nn) in [(2.0, 0.0, 'clean'), (3.0, 3.0, 'typical'), (5.0, 5.0, 'rough')]) {
      test('$nn GPS: off a road, round a block, round a park, out and back, to a fountain', () {
        final o = Oval.lane(1);
        final lat = <String, List<double>>{}, err = <String, List<double>>{};
        void note(String k, double latency, double e) {
          (lat[k] ??= []).add(latency);
          (err[k] ??= []).add(e);
        }

        for (var seed = 1; seed <= 12; seed++) {
          final truth = truthFor(seed), track = OnTrack(o, truth, o.uFinish, 1);
          final acc = 4 + sg;
          // a road run from the start: 600 m east, 500 m north, 400 m west
          final road = Polyline([const Pt(0, 0), const Pt(600, 0), const Pt(600, 500), const Pt(200, 500)]);
          var out = runCourse(road, road.length, seed: seed, sigma: sg, drift: dr, acc: acc);
          expect(out.offAt.map((x) => x.$2).toList(), [true], reason: 'road seed $seed ${offs(out)}');
          note('road', out.offAt.first.$1, (metresOf(out) - out.metres) / out.metres);
          // round a 250 x 150 m block, three times
          final block = Polyline([
            for (var i = 0; i < 3; i++) ...[const Pt(0, 0), const Pt(250, 0), const Pt(250, 150), const Pt(0, 150)],
            const Pt(0, 0),
          ]);
          out = runCourse(block, block.length, seed: seed, sigma: sg, drift: dr, acc: acc);
          expect(out.offAt.map((x) => x.$2).toList(), [true], reason: 'block seed $seed ${offs(out)}');
          note('block', out.offAt.first.$1, (metresOf(out) - out.metres) / out.metres);
          // round a park, a 100 m circle, three times: a loop, but no track
          final park = Polyline([
            for (var i = 0; i <= 360; i++)
              Pt(100 * math.cos(i * 2 * math.pi / 120) - 100, 100 * math.sin(i * 2 * math.pi / 120)),
          ]);
          out = runCourse(park, park.length, seed: seed, sigma: sg, drift: dr, acc: acc);
          expect(out.offAt.map((x) => x.$2).toList(), [true], reason: 'park seed $seed ${offs(out)}');
          note('park', out.offAt.first.$1, (metresOf(out) - out.metres) / out.metres);
          // 1.5 laps, 800 m out on a road and back, 2 laps
          final uL = o.uFinish + 600 / o.perim, leave = track.at(600), e = truth.apply(leave), n = outward(o, uL);
          final outPt = truth.invert(Pt(e.x + n.x * 800, e.y + n.y * 800));
          final there = Polyline([leave, outPt, leave]);
          out = runCourse(
            Joined([(track, 600), (there, there.length), (OnTrack(o, truth, uL, 1), 2 * o.perim)]),
            600 + there.length + 2 * o.perim,
            seed: seed,
            sigma: sg,
            drift: dr,
            acc: acc,
          );
          expect(out.offAt.map((x) => x.$2).toList(), [true, false], reason: 'out and back seed $seed ${offs(out)}');
          expect(out.offAt.last.$1 - (600 + there.length), lessThan(120), reason: 'back on soon after');
          note('out and back', out.offAt.first.$1 - 600, (metresOf(out) - out.metres) / out.metres);
          // 1.5 laps, 50 m off the outside to a fountain, back, 2 laps
          final f = truth.invert(Pt(e.x + n.x * 50, e.y + n.y * 50));
          final side = Polyline([leave, f, leave]);
          out = runCourse(
            Joined([(track, 600), (side, side.length), (OnTrack(o, truth, uL, 1), 2 * o.perim)]),
            600 + side.length + 2 * o.perim,
            seed: seed,
            sigma: sg,
            drift: dr,
            acc: acc,
          );
          expect(out.offAt.isEmpty || out.offAt.last.$2 == false, isTrue, reason: 'fountain seed $seed ${offs(out)}');
          expect(out.r.laps.length, 3);
          note(
            'fountain',
            out.offAt.isEmpty ? double.nan : out.offAt.first.$1 - 600,
            (metresOf(out) - out.metres) / out.metres,
          );
        }
        for (final k in lat.keys) {
          final e = [for (final v in err[k]!) v.abs()], l = lat[k]!.where((v) => v.isFinite).toList();
          summary.add(
            '${'off, $k, $nn GPS'.padRight(34)} '
            '${l.isEmpty ? 'never called off' : 'noticed after ${pct(l, .5).round()} m off (p95 ${pct(l, .95).round()}, ${l.length}/12 runs)'}, '
            'distance off by ${(pct(e, .5) * 100).toStringAsFixed(1)}% (p95 ${(pct(e, .95) * 100).toStringAsFixed(1)}%)',
          );
          // a 50 m step off in rough GPS can go unnoticed: the laps still count, the 100 m detour is lost
          expect(pct(e, .95), lessThan(k == 'fountain' ? (nn == 'rough' ? 0.09 : 0.03) : 0.03), reason: k);
        }
        // over 12 runs this is about the worst one; over 100 rough-GPS runs p50 is 185 m, p95 228 m
        expect(pct(lat['road']!, .95), lessThan(270));
        expect(pct(lat['out and back']!, .95), lessThan(90));
      });
    }
    test('off the track the laps row shows lap equivalents of the distance', () {
      final road = Polyline([const Pt(0, 0), const Pt(2000, 0)]);
      final out = runCourse(road, 1800, seed: 5, sigma: 2, acc: 6, lane: 2);
      final s = stats(out.r, out.t, fracs(out.r));
      expect(out.r.off, isTrue);
      expect(s.n, (s.metres / laneLength(2)).floor());
      expect(s.n, 4);
      expect(s.avgLap, closeTo(s.el * laneLength(2) / s.metres, 1));
    });
  });

  test('sensing and off-track state survive a save and restore', () {
    final o = Oval.lane(2), truth = truthFor(7);
    final out = runCourse(OnTrack(o, truth, o.uFinish + 100 / o.perim, -1), 500, seed: 7, sigma: 2, acc: 6, lane: 2);
    final back = Run.fromJson(out.r.toJson());
    expect(back.sense, out.r.sense);
    expect(back.dir, -1);
    expect(back.uStart, out.r.uStart);
    expect(back.geo!.apply(const Pt(10, 20)).dist(out.r.geo!.apply(const Pt(10, 20))), lessThan(1e-9));
    final t = trackOf(out.r, 1)!;
    final again = Geo.centred((t['a'] as num).toDouble(), out.r.geo!.centre.x, out.r.geo!.centre.y);
    expect(again.apply(const Pt(5, 5)).dist(out.r.geo!.apply(const Pt(5, 5))), lessThan(1e-6));
    expect(withTrack([t], t).length, 1, reason: 'the same track is kept once');
  });
}
