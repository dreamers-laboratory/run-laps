# Changelog

## Android 1.2.0 (3), patch 2

- A jump in GPS position (a stale first fix, or a GPS simulator) is no longer counted as running: no laps or impossible speeds from it, and a run that has not moved yet starts where GPS settled.
- No lap is ever counted quicker than a world record.

## 1.2.1 (4) - iOS TestFlight

- Explain why location is needed during a run, including when the screen is locked.
- Remove the unused Always permission request from the iOS release build.
- Add Settings → About with links to the source code and Dreamers Inc.
