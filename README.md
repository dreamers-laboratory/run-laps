# run laps

Created by [Dreamers Inc.](https://thedreamers.us/).

A GPS lap counter for a running track, drawn in pencil. Android.

- Pick a distance and your lane. Laps and distance use that lane's real length (lane 1 is 400 m, lane 8 is 453 m).
- Press ▶ and run. Hold ■ for 3 seconds to stop.
- By the end of the first bend it knows the track's shape, your direction and where you started, and it remembers the track for next time.
- Leave the track and it says "Run Forrest run!", draws your route up the page and keeps the distance from GPS.
- Tap the empty top-left corner of the run screen to see GPS accuracy.
- Profile → advanced: the track it found, battery mode, a lap bell.

## Build

Flutter 3.47 or newer.

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Allow precise location while using the app.

## Battery mode

On by default. The run screen is a little dimmer while you run. It can also turn on the phone's battery saver for the run and turn it back off when you stop, once you allow it over USB:

```bash
adb shell pm grant us.thedreamers.laps android.permission.WRITE_SECURE_SETTINGS
```

## Tests

```bash
flutter test
```

Simulated runners on a noisy GPS: every lane, track sensing, runs off the track, a marathon.

## License

[WTFPL](LICENSE). Red Hat Mono is under the [SIL Open Font License](assets/fonts/OFL.txt).
