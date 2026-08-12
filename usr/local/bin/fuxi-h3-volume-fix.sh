#!/bin/bash
#
# Havit Fuxi-H3 — force hardware volume to 100%.
# The dongle mutes one channel below 100%; the real volume is handled by the
# PipeWire soft-mixer (see wireplumber/fuxi-h3-fix.conf).
#
# Runs from:
#   - udev (hotplug): exits 0 silently if the card isn't ready yet
#   - systemd user service (FUXI_H3_RETRY=1): exits 1 so systemd retries
#
# Idempotent — safe to run any time.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

sleep 2
CARD=$(grep -iE 'FuxiH3|Fuxi-H3' /proc/asound/cards 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$CARD" ]; then
  [ "${FUXI_H3_RETRY:-0}" = "1" ] && exit 1
  exit 0
fi

# PCM,0: stereo volume (Front Left/Right)
/usr/bin/amixer -c "$CARD" sset 'PCM',0 100%,100% > /dev/null 2>&1
# PCM,1: mute switch on some firmwares, volume on others — cover both
/usr/bin/amixer -c "$CARD" sset 'PCM',1 100% > /dev/null 2>&1
/usr/bin/amixer -c "$CARD" sset 'PCM',1 on    > /dev/null 2>&1

exit 0
