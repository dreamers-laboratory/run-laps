import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

const _ch = MethodChannel('laps');

/// The lap bell, mixed over whatever music is playing.
Future<void> ringBell() => _ch.invokeMethod('bell', bell);

/// The phone's battery saver on or off; true if it changed. Allowed only once granted over adb.
Future<bool> batterySaver(bool on) async => await _ch.invokeMethod<bool>('saver', on) ?? false;
Future<bool> canSetSaver() async => await _ch.invokeMethod<bool>('canSave') ?? false;

/// Ask to be left out of Android's battery optimisation, so a run keeps going with the screen off.
Future<void> unrestrict() => _ch.invokeMethod('unrestrict');

/// A small meditation bell, 16-bit mono at 44.1 kHz: a soft strike, singing-bowl partials and a slow
/// beat, gone in two seconds.
final Uint8List bell = () {
  const rate = 44100, secs = 2.2, f0 = 660.0;
  const partials = [(1.0, 1.0, 0.9), (1.0024, 0.35, 0.9), (2.76, 0.3, 0.45), (5.4, 0.1, 0.25), (8.93, 0.03, 0.15)];
  final out = Int16List((rate * secs).round());
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    var v = 0.0;
    for (final (ratio, level, decay) in partials) {
      v += level * math.exp(-t / decay) * math.sin(2 * math.pi * f0 * ratio * t);
    }
    final strike = math.pow(math.sin(math.min(1, t / 0.012) * math.pi / 2), 2);
    final tail = math.min(1.0, (secs - t) / 0.3);
    out[i] = (v * strike * tail * 0.4 * 32767).round();
  }
  return out.buffer.asUint8List();
}();
