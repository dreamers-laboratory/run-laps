// The off-track drawing: routes grown point by point, as a run would, checked at every step.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:laps/engine.dart';
import 'package:laps/painters.dart';

/// The route box of look a on a Pixel 8 (411 x 914 dp): 40% of the width, 30% of the height.
const box = Size(0.4 * (411 - 32), 0.3 * 914);

List<Pt> lapOf(double turn) {
  final o = Oval.lane(2), c = math.cos(turn), s = math.sin(turn);
  return [
    for (var i = 0; i <= 136; i++)
      () {
        final p = o.along(o.uFinish + i / 136);
        return Pt(p.x * c - p.y * s, -(p.x * s + p.y * c));
      }(),
  ];
}

/// Straight on from the last point: heading in degrees from east, every 3 m.
List<Pt> go(List<Pt> r, double deg, double metres) {
  final a = deg * math.pi / 180;
  return [for (var m = 3.0; m <= metres; m += 3) Pt(r.last.x + m * math.cos(a), r.last.y + m * math.sin(a))];
}

/// Round a circle of radius rad, starting where you are, heading deg, turning left (or right).
List<Pt> loop(List<Pt> r, double deg, double rad, {double turns = 1, bool left = true}) {
  final a = deg * math.pi / 180, side = left ? 1 : -1, p = r.last;
  final cx = p.x - side * rad * math.sin(a), cy = p.y + side * rad * math.cos(a);
  final n = (2 * math.pi * rad * turns / 3).round();
  return [
    for (var i = 1; i <= n; i++)
      () {
        final t = a - side * math.pi / 2 + side * 2 * math.pi * turns * i / n;
        return Pt(cx + rad * math.cos(t), cy + rad * math.sin(t));
      }(),
  ];
}

Map<String, List<Pt>> routes() {
  final rnd = math.Random(5);
  List<Pt> r;
  final out = <String, List<Pt>>{};
  r = lapOf(0.3);
  r += go(r, 20, 900);
  out['a lap, then 900 m up a road'] = r;
  r = lapOf(1.2);
  r += go(r, 200, 300);
  r += loop(r, 200, 120);
  r += go(r, 20, 300);
  out['a lap, out 300 m, round a park, back'] = r;
  r = lapOf(2.0);
  r += go(r, 110, 400);
  r += loop(r, 110, 90);
  r += loop(r, 110, 90, left: false);
  out['a lap, out 400 m, a figure 8'] = r;
  r = lapOf(0.0);
  r += go(r, 300, 1200);
  r += go(r, 120, 1150);
  out['a lap, out 1.2 km and back the same road'] = r;
  r = [const Pt(0, 0)];
  r += go(r, 0, 1500);
  r += go(r, 90, 900);
  out['an L: 1.5 km east, 900 m north'] = r;
  r = [const Pt(0, 0)];
  var h = 45.0;
  for (var i = 0; i < 1000; i++) {
    h += (rnd.nextDouble() - 0.5) * 30;
    r += go(r, h, 3);
  }
  out['a 3 km wander'] = r;
  r = [const Pt(0, 0)];
  for (var i = 1; i <= 900; i++) {
    final t = i * 0.035, rad = 4.0 * t;
    r.add(Pt(rad * math.cos(t), rad * math.sin(t)));
  }
  out['a spiral outward'] = r;
  return out;
}

/// Signed area of the route closed back to its start (the same wherever it sits).
double area(List<Pt> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final q = p[i], r = p[(i + 1) % p.length];
    a += q.x * r.y - r.x * q.y;
  }
  return a;
}

void main() {
  final aspect = routeAspect(box);
  final summary = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('\n${summary.join('\n')}');
  });

  for (final MapEntry(key: name, value: all) in routes().entries) {
    // turns are counted from when you would leave the track (after the lap), the rest from the first point
    final offFrom = name.startsWith('a lap') ? 157 : 20;
    test(name, () {
      RouteShape? prev;
      var turns = 0, flips = 0, worstFill = 1.0;
      double? firstScale, lastScale;
      final history = <String>[];
      for (var n = 20; n <= all.length; n += 5) {
        final raw = all.sublist(0, n);
        final r = RouteShape(raw, aspect: aspect, prev: prev);
        final f = routeFrame(r, box);
        // inside the box, clear of the ruler strip
        for (final q in r.pts.whereType<Pt>()) {
          final x = f.ox + q.x * f.s, y = f.oy + q.y * f.s;
          expect(x, inInclusiveRange(54 - 1e-6, box.width + 1e-6), reason: '$name n=$n');
          expect(y, inInclusiveRange(-1e-6, box.height + 1e-6), reason: '$name n=$n');
        }
        // true to shape: turned only, never stretched or mirrored
        final out = r.pts.whereType<Pt>().toList();
        for (final (i, j) in [(0, n - 1), (0, n ~/ 2), (n ~/ 3, n - 2)]) {
          expect(out[i].dist(out[j]), closeTo(raw[i].dist(raw[j]), 1e-6));
        }
        // screen y points down, ground y points up: a proper turn flips the sign of the area
        if (area(raw).abs() > 100) expect(area(out).sign, -area(raw).sign, reason: 'mirrored at n=$n');
        // as big as it can be, near enough (it holds its turn until another is 10% bigger)
        final hull = raw;
        var best = 0.0;
        for (var k = 0; k < 180; k++) {
          best = math.max(best, RouteShape.fitAt(hull, k * math.pi / 180, aspect));
        }
        final fill = RouteShape.fitAt(hull, r.angle, aspect) / best;
        worstFill = math.min(worstFill, fill);
        // the start stays low: never in the top 30%
        expect(r.start!.y, greaterThanOrEqualTo(0.3 * r.h - 1e-6), reason: '$name start up at n=$n');
        if (prev != null && n >= offFrom) {
          if ((r.angle - prev.angle).abs() > 1e-9) {
            turns++;
            history.add('turn@$n');
          }
          if (r.flip != prev.flip) {
            flips++;
            history.add('flip@$n');
          }
        }
        firstScale ??= f.s;
        lastScale = f.s;
        prev = r;
      }
      summary.add(
        '${name.padRight(40)} ${(all.length * 3 / 1000).toStringAsFixed(1)} km: turned $turns×, flipped $flips×, '
        'drawn at ≥${(worstFill * 100).round()}% of the biggest it could be, scale ${firstScale!.toStringAsFixed(2)} → ${lastScale!.toStringAsFixed(2)} px/m ${history.take(8).join(' ')}',
      );
      expect(worstFill, greaterThan(0.8));
      // a spiral changes shape with every metre, so it turns often; real routes settle
      if (!name.contains('spiral')) {
        expect(turns, lessThanOrEqualTo(4), reason: history.join(' '));
        expect(flips, lessThanOrEqualTo(2), reason: history.join(' '));
      }
      expect(lastScale, lessThan(firstScale), reason: 'the drawing shrinks as the route grows');
    });
  }
}
