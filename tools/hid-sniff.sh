#!/bin/bash
#
# Capture HID reports from the Fuxi-H3 dongle (hidraw).
# While capturing, press buttons on the headset (volume +/-, mic mute, power)
# — the dongle's status/battery/button reports show up as hex, which is the
# starting point for reverse-engineering vendor commands (e.g. auto power-off).
#
# Usage: ./tools/hid-sniff.sh [seconds]    (default 30)

set -euo pipefail

HID=""
for h in /dev/hidraw*; do
  [ -e "$h" ] || continue
  if udevadm info -q path -n "$h" 2>/dev/null | grep -qi '040B:0897'; then
    HID="$h"
    break
  fi
done

if [ -z "$HID" ]; then
  echo "Fuxi-H3 hidraw device not found — dongle plugged in?" >&2
  echo "Rule installed? (udev rule adds MODE=0666 to the hidraw device)" >&2
  exit 1
fi

echo "Capturing from $HID — press buttons on the headset now!"
echo "Ctrl+C to stop. Each line = one report (hex bytes)."
timeout "${1:-30}" cat "$HID" | xxd -g1
