import 'package:flutter_test/flutter_test.dart';
import 'package:laps/engine.dart';
import 'package:laps/goal.dart';

void main() {
  test('half marathon shows 13.1; typing 13.1 picks it back', () {
    final g = Goal();
    expect(g.preset, 'half');
    expect(g.fieldText, '13.1');
    for (final (typed, want) in [
      ('26.2', 'marathon'),
      ('13.1', 'half'),
      ('6.2', '10k'),
      ('3.1', '5k'),
      ('1', 'mile'),
      ('10 mi', '10mi'),
      ('5k', '5k'),
      ('7', ''),
    ]) {
      expect(g.takeTyped(typed), isTrue, reason: typed);
      expect(g.preset, want, reason: typed);
    }
  });
  test('picking a preset fills the amount', () {
    final g = Goal()..pickPreset('5k');
    expect(g.fieldText, '3.1');
    g.pickPreset('marathon');
    expect(g.fieldText, '26.2');
  });
  test('laps unit converts with the lane', () {
    final g = Goal()..setUnit('laps');
    expect(g.fieldText, '52.7');
    g.setLane(4);
    expect(g.fieldText, '50'); // 21097.5 / 422.37 = 49.95
    expect(g.takeTyped('12.5'), isTrue);
    expect(g.preset, ''); // 12.5 laps of lane 4 is 5.28 km, not a 5K
    g.setLane(1);
    expect(g.takeTyped('12.5'), isTrue);
    expect(g.preset, '5k');
  });
  test('a laps goal stays laps when the lane changes, a distance stays a distance', () {
    final g = Goal()..setUnit('laps');
    g.takeTyped('40');
    g.setLane(4);
    expect(g.laps, closeTo(40, 1e-9));
    expect(g.metres, closeTo(40 * laneLength(4), 1e-6));
    g.pickPreset('half');
    g.setLane(2);
    expect(g.metres, 21097.5);
  });
  test('parsing', () {
    expect(parseGoal('5k', 'mi')!.m, 5000);
    expect(parseGoal('40 laps', 'mi')!.laps, 40);
    expect(parseGoal('1500m', 'mi')!.m, 1500);
    expect(parseGoal('5m', 'mi')!.m, closeTo(5 * mile, 1e-6));
    expect(parseGoal('13.', 'mi')!.m, closeTo(13 * mile, 1e-6));
    expect(parseGoal('half', 'mi')!.m, 21097.5);
    expect(parseGoal('abc', 'mi'), isNull);
    expect(parseGoal('', 'mi'), isNull);
  });
  test('saved settings come back', () {
    final g = Goal(preset: '', unit: 'laps', value: 40, lane: 2);
    final b = Goal.fromJson(g.toJson());
    expect((b.preset, b.unit, b.value, b.lane), ('', 'laps', 40.0, 2));
  });
}
