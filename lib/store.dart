import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Settings, the run in progress and the history, kept on the phone.
class Store {
  static SharedPreferences? _p;
  static Future<void> init() async => _p ??= await SharedPreferences.getInstance();

  static dynamic get(String k) {
    final s = _p?.getString(k);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String k, Object? v) async {
    if (_p == null) return;
    if (v == null) {
      await _p!.remove(k);
    } else {
      await _p!.setString(k, jsonEncode(v));
    }
  }

  static bool flag(String k) => _p?.getBool(k) ?? false;
  static Future<void> setFlag(String k) async => _p?.setBool(k, true);

  static List<Map<String, dynamic>> history() => [
    for (final e in (get('laps.history') as List? ?? [])) (e as Map).cast<String, dynamic>(),
  ];

  static Future<void> saveHistory(List<Map<String, dynamic>> h) => set('laps.history', h.take(200).toList());

  /// Tracks sensed on earlier runs: where they lie, their shape, which way you ran.
  static List<Map<String, dynamic>> tracks() => [
    for (final e in (get('laps.tracks') as List? ?? [])) (e as Map).cast<String, dynamic>(),
  ];
  static Future<void> saveTracks(List<Map<String, dynamic>> t) => set('laps.tracks', t);

  /// Which way round you run where no track is known yet: 1 counter-clockwise, -1 clockwise.
  static int defaultDir() => (get('laps.dir') as num?)?.toInt() ?? 1;
  static Future<void> setDefaultDir(int d) => set('laps.dir', d);
}
