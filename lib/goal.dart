// The goal and the lane. The dropdown and the amount box are one value: picking half marathon
// shows 13.1, typing 13.1 (or 52.7 laps, or 21.1k) picks half marathon.
import 'engine.dart';

class Preset {
  final String k, label;
  final double m;
  final num mi; // the number runners call it
  const Preset(this.k, this.label, this.m, this.mi);
}

const presets = [
  Preset('mile', '1 mile', mile, 1),
  Preset('5k', '5K', 5000, 3.1),
  Preset('10k', '10K', 10000, 6.2),
  Preset('10mi', '10 miles', 10 * mile, 10),
  Preset('half', 'half marathon', 21097.5, 13.1),
  Preset('marathon', 'marathon', 42195, 26.2),
];

Preset? presetOf(String k) => presets.where((p) => p.k == k).firstOrNull;

/// Within half a percent counts as the race: 13.1 mi is the half, 3.1 the 5K.
Preset? matchPreset(double m) => presets.where((p) => (m - p.m).abs() / p.m < 0.005).firstOrNull;

typedef Parsed = ({double? m, double? laps});

Parsed? parseGoal(String text, String unit) {
  final s = text.trim().toLowerCase().replaceAll(',', '.').replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  const named = {
    'half': 21097.5,
    'half marathon': 21097.5,
    'half-marathon': 21097.5,
    'hm': 21097.5,
    'marathon': 42195.0,
    'full': 42195.0,
    'full marathon': 42195.0,
    'mile': mile,
    'a mile': mile,
  };
  if (named.containsKey(s)) return (m: named[s], laps: null);
  final g = RegExp(r'^(\d+\.?\d*|\.\d+)\s*([a-z]*)$').firstMatch(s);
  if (g == null) return null;
  final n = double.tryParse(g.group(1)!);
  final u = g.group(2)!;
  if (n == null || !(n > 0)) return null;
  Parsed? out;
  if (const ['k', 'km', 'kms', 'kilometer', 'kilometers', 'kilometre', 'kilometres'].contains(u)) {
    out = (m: n * 1000, laps: null);
  } else if (const ['mi', 'mile', 'miles', 'mis'].contains(u)) {
    out = (m: n * mile, laps: null);
  } else if (const ['l', 'lap', 'laps'].contains(u)) {
    out = (m: null, laps: n);
  } else if (const ['m', 'meter', 'meters', 'metre', 'metres'].contains(u)) {
    out = (m: u == 'm' && n < 100 ? n * mile : n, laps: null);
  } else if (u.isEmpty) {
    out = unit == 'laps' ? (m: null, laps: n) : (m: n * mile, laps: null);
  }
  if (out == null) return null;
  if ((out.m ?? 0) > 400 * mile || (out.laps ?? 0) > 2000) return null;
  return out;
}

String trim2(double x) {
  final r = (x * 100).round() / 100;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

String lapsTxt(double x) {
  final r = (x * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

class Goal {
  String preset; // '' = custom
  String unit; // 'mi' | 'laps'
  double value; // in unit, for a custom goal
  int lane; // 1..8 on a 400 m track
  Goal({this.preset = 'half', this.unit = 'mi', this.value = 13.1, this.lane = 1});

  double get lapM => laneLength(lane);
  double get metres {
    final p = presetOf(preset);
    if (p != null) return p.m;
    return unit == 'laps' ? value * lapM : value * mile;
  }

  double get laps => metres / lapM;

  /// The amount in the box, in the unit you chose.
  String get fieldText {
    final p = presetOf(preset);
    if (p != null) return unit == 'laps' ? lapsTxt(p.m / lapM) : '${p.mi}';
    return trim2(value);
  }

  String get label {
    final p = presetOf(preset);
    return p != null ? p.label : '${trim2(value)} $unit';
  }

  /// A typed amount; false if it doesn't read as a distance.
  bool takeTyped(String text) {
    final g = parseGoal(text, unit);
    if (g == null) return false;
    final m = g.m ?? g.laps! * lapM;
    final p = matchPreset(m);
    unit = g.laps != null ? 'laps' : 'mi';
    if (p != null) {
      preset = p.k;
    } else {
      preset = '';
      value = unit == 'laps' ? (g.laps ?? m / lapM) : m / mile;
    }
    return true;
  }

  void pickPreset(String k) {
    if (k.isNotEmpty) {
      preset = k;
    } else {
      final m = metres;
      preset = '';
      value = unit == 'laps' ? m / lapM : m / mile;
    }
  }

  void setUnit(String u) {
    if (u == unit) return;
    final m = metres;
    unit = u;
    if (preset.isEmpty) value = unit == 'laps' ? m / lapM : m / mile;
  }

  /// A laps goal stays that many laps in the new lane; a distance stays that distance.
  void setLane(int l) => lane = l.clamp(1, 8);

  Map<String, dynamic> toJson() => {'preset': preset, 'unit': unit, 'value': value, 'lane': lane};
  static Goal fromJson(Map<String, dynamic>? j) => j == null
      ? Goal()
      : Goal(
          preset: j['preset'] as String? ?? 'half',
          unit: j['unit'] as String? ?? 'mi',
          value: (j['value'] as num? ?? 13.1).toDouble(),
          lane: (j['lane'] as num? ?? 1).toInt().clamp(1, 8),
        );
}
