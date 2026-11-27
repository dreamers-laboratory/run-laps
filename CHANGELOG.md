# Changelog

## Android 1.2.0 (3), patch 3

- Every speed cap is the world record run 20% faster: 12.53 m/s for any moment (100 m in 9.58 s), 11.16 m/s for a lap (400 m in 43.03 s), so a 400 m lap counts down to 35.9 s.
- A redrawn track no longer wipes the lap in progress when the first fix sat a little off it (rough GPS lost a lap in about 1 run in 25).

## Android 1.2.0 (3), patch 2

- A jump in GPS position (a stale first fix, or a GPS simulator) is no longer counted as running: no laps or impossible speeds from it, and a run that has not moved yet starts where GPS settled.
- No lap is ever counted quicker than a world record.

## 1.2.1 (4) - iOS TestFlight

- Explain why location is needed during a run, including when the screen is locked.
- Remove the unused Always permission request from the iOS release build.
- Add Settings → About with links to the source code and Dreamers Inc.
