# run laps

Created by [Dreamers Inc.](https://thedreamers.us/).

A GPS lap counter for a running track, drawn in pencil. Android and iPhone.

- Pick a distance and your lane. Laps and distance use that lane's real length (lane 1 is 400 m, lane 8 is 453 m).
- Press ▶ and run. Hold ■ for 3 seconds to stop.
- By the end of the first bend it knows the track's shape, your direction and where you started, and it remembers the track for next time.
- Leave the track and it says "Run Forrest run!", draws your route up the page and keeps the distance from GPS.
- Tap the empty top-left corner of the run screen to see GPS accuracy.
- Profile → advanced: the track it found, battery mode, a lap bell.

## Build

Flutter 3.47 or newer.

Android:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

iPhone (Xcode; set your own signing team in `ios/Runner.xcodeproj` to run it on a phone):

```bash
flutter run --release
```

Allow precise location while using the app.

### TestFlight builds

Use When In Use authorization for GPS. Start the run while the app is open;
background location updates let an active run keep counting when the screen locks.
Keep the unused Always authorization request out of the iOS binary:

```bash
XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/LocationAuthorization.xcconfig" \
  flutter build ipa --release --no-codesign
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist /path/to/ExportOptions.plist -exportPath build/ios/ipa
bash tool/check_ios_ipa.sh build/ios/ipa/laps.ipa
```

Export using your team's App Store Connect signing settings, then run the check
on the exact signed IPA you intend to upload.

## Battery mode

On by default. The run screen is a little dimmer while you run. On Android it can also turn on the phone's battery saver for the run and turn it back off when you stop, once you allow it over USB:

```bash
adb shell pm grant us.thedreamers.laps android.permission.WRITE_SECURE_SETTINGS
```

## Tests

```bash
flutter test
```

Simulated runners on a noisy GPS: every lane, track sensing, runs off the track, a marathon.

## License

Run Laps' original source is licensed under [Apache 2.0](LICENSE).
See [NOTICE](NOTICE) for original-author attribution.

The [earlier source revisions](https://github.com/dreamers-laboratory/run-laps/blob/dfac2ce163a95846f73ea948cddc74fa6ee29eaf/LICENSE)
remain available under their historical WTFPL license.

Red Hat Mono retains the [SIL Open Font License](assets/fonts/OFL.txt).
The Flutter-generated platform scaffold retains
[Flutter's BSD 3-Clause license](licenses/flutter.txt). Dependencies retain
their own licenses.
