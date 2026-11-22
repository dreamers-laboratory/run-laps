import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'engine.dart';

enum GpsState { waiting, ok, denied, off, approx, lost }

/// The GPS chip itself (LocationManager's GPS provider), one fix a second with its Doppler speed.
/// During a run it runs in a location foreground service, so it keeps going with the screen off.
class Gps {
  final void Function(Fix) onFix;
  final VoidCallback onChange;
  GpsState state = GpsState.waiting;
  Fix? last;
  bool _foreground = false;
  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _svc;
  Timer? _watch;

  Gps(this.onFix, this.onChange);

  Future<void> init() async {
    _svc = Geolocator.getServiceStatusStream().listen(
      (s) => s == ServiceStatus.disabled ? _set(GpsState.off) : start(foreground: _foreground),
    );
    _watch = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state == GpsState.ok && last != null && DateTime.now().millisecondsSinceEpoch - last!.t > 10000) {
        _set(GpsState.lost);
      }
    });
    await start(foreground: false);
  }

  void _set(GpsState s) {
    if (state == s) return;
    state = s;
    onChange();
  }

  /// Precise location while the app is in use. Approximate is no use on a track.
  Future<bool> ensure() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _set(GpsState.off);
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
      _set(GpsState.denied);
      return false;
    }
    if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
      _set(GpsState.approx);
    } else if (const [GpsState.denied, GpsState.off, GpsState.approx].contains(state)) {
      _set(GpsState.waiting);
    }
    return true;
  }

  Future<void> start({required bool foreground}) async {
    _foreground = foreground;
    if (!await ensure()) return;
    await _sub?.cancel();
    _sub =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            forceLocationManager: true,
            foregroundNotificationConfig: foreground
                ? const ForegroundNotificationConfig(
                    notificationTitle: 'run laps',
                    notificationText: 'counting your laps',
                    notificationChannelName: 'Run',
                    notificationIcon: AndroidResource(name: 'ic_stat_laps', defType: 'drawable'),
                    enableWakeLock: true,
                    setOngoing: true,
                  )
                : null,
          ),
        ).listen(
          _onPos,
          onError: (Object e) {
            debugPrint('LAPS gps error $e');
            _set(GpsState.lost);
          },
        );
    debugPrint('LAPS gps listening foreground=$foreground');
  }

  void _onPos(Position p) {
    final f = Fix(
      p.latitude,
      p.longitude,
      p.accuracy,
      DateTime.now().millisecondsSinceEpoch,
      spd: p.hasSpeed ? p.speed : null,
      spdAcc: p.hasSpeedAccuracy && p.speedAccuracy > 0 ? p.speedAccuracy : null,
    );
    last = f;
    if (state != GpsState.approx) state = GpsState.ok;
    onFix(f);
    onChange();
  }

  Future<void> openSettings() =>
      state == GpsState.off ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();

  void dispose() {
    _sub?.cancel();
    _svc?.cancel();
    _watch?.cancel();
  }
}
