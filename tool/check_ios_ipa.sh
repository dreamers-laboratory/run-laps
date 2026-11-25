#!/bin/bash
set -euo pipefail

ipa=${1:?Usage: check_ios_ipa.sh /path/to/laps.ipa}
app=Payload/Runner.app
plist=$(unzip -p "$ipa" "$app/Info.plist" | plutil -convert xml1 -o - -)

read_plist() {
    printf '%s\n' "$plist" | plutil -extract "$1" raw -o - -
}

for key in NSLocationWhenInUseUsageDescription NSLocationAlwaysAndWhenInUseUsageDescription; do
    if [ -z "$(read_plist "$key" 2>/dev/null)" ]; then
        printf 'Missing %s in the signed IPA\n' "$key" >&2
        exit 1
    fi
done

if ! printf '%s\n' "$plist" | plutil -extract UIBackgroundModes json -o - - |
    grep -E '"location"' >/dev/null; then
    printf 'Background location mode is missing\n' >&2
    exit 1
fi

executable=$(read_plist CFBundleExecutable)
# The geolocator Swift package links into the Runner executable.
if ! unzip -p "$ipa" "$app/$executable" | strings | awk '
    $0 == "requestWhenInUseAuthorization" { whenInUse = 1 }
    $0 == "requestAlwaysAuthorization" { always = 1 }
    END { exit !(whenInUse && !always) }
'; then
    printf 'Location authorization check failed; rebuild with BYPASS_PERMISSION_LOCATION_ALWAYS=1\n' >&2
    exit 1
fi

printf '%s %s (%s): location metadata and When In Use authorization verified\n' \
    "$(read_plist CFBundleIdentifier)" "$(read_plist CFBundleShortVersionString)" "$(read_plist CFBundleVersion)"
