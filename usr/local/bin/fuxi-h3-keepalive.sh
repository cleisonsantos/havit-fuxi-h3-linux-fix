#!/bin/bash
#
# Havit Fuxi-H3 — keep-alive: streams continuous silence to the dongle so the
# headset never goes idle and triggers its auto power-off (which is handled by
# the headset firmware and cannot be disabled from the OS).
#
# Trade-off: the RF link stays active -> slightly higher battery drain.
# Toggle with: systemctl --user start|stop fuxi-h3-keepalive.service

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

while true; do
  SINK=$(pactl list sinks short 2>/dev/null | grep -i fuxi | awk '{print $2}')
  if [ -z "$SINK" ]; then
    sleep 5   # dongle not plugged in (yet) — retry
    continue
  fi
  # /dev/zero = endless silence (raw s16le). If pw-cat exits (replug,
  # pipewire restart), loop again — sub-second gaps are inaudible.
  pw-cat --playback --raw --format s16 --rate 48000 --channels 2 --target "$SINK" /dev/zero
  sleep 1
done
