// A marathon on the track: 103.7 laps of lane 2, many runners, GPS from clean to bad.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:laps/engine.dart';

import 'sim.dart';

void main() {
  const marathon = 42195.0;
  final rows = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('\n${rows.join('\n')}');
  });
  // name, white noise per fix (m), slow wander (m), the accuracy the phone would show (m), GPS gaps
  const cases = [
    ('clean, shows ~4 m', 1.5, 1.0, 4.0, false),
    ('typical, shows ~6 m', 3.0, 3.0, 6.0, false),
    ('rough, shows ~10 m', 5.0, 5.0, 10.0, false),
    ('bad, shows ~14 m', 7.0, 7.0, 14.0, false),
    ('very bad, shows ~20 m', 10.0, 10.0, 20.0, false),
    ('typical + a 20 s gap every 2 km', 3.0, 3.0, 6.0, true),
  ];
  for (final (name, sg, dr, acc, gaps) in cases) {
    test(name, () {
      final errs = <double>[], missed = <int>[];
      var offs = 0;
      for (var seed = 1; seed <= 12; seed++) {
        final o = Oval.lane(2), truth = Geo.centred(seed * 0.7, 0, 0);
        final c = OnTrack(o, truth, o.uFinish + 60 / o.perim, 1);
        final out = runCourse(
          c,
          marathon,
          seed: seed,
          sigma: sg,
          drift: dr,
          acc: acc,
          lane: 2,
          speed: gaps ? (m, t) => 3.4 : null,
          gapEvery: gaps ? 2000 : 0,
          gapSecs: 20,
        );
        final s = stats(out.r, out.t, fracs(out.r));
        errs.add((s.metres - out.metres) / out.metres * 100);
        missed.add((out.metres / o.perim).floor() - out.r.laps.length);
        if (out.offAt.isNotEmpty) offs++;
      }
      final abs = [for (final e in errs) e.abs()]..sort();
      rows.add(
        '${name.padRight(34)} distance off by ${pct(abs, .5).toStringAsFixed(2)}% (worst ${abs.last.toStringAsFixed(2)}%), '
        'laps missed per marathon ${missed.reduce(math.min)}..${missed.reduce(math.max)}, false off-track $offs/12',
      );
      // up to what a phone shows as ~14 m, every lap counts and a marathon comes out within 1%;
      // past that (~20 m) GPS is too rough to tell laps apart, and this run only records how it goes
      if (acc <= 14) {
        expect(abs.last, lessThan(1.0), reason: name);
        expect(missed.every((x) => x == 0), isTrue, reason: name);
      }
    });
  }
}
