#!/usr/bin/env bash
#
# Havit Fuxi-H3 — verify the fix is applied.
# Exit codes: 0 = all checks passed, 1 = something failed, 2 = dongle not detected.

set -uo pipefail

PASS=0; FAIL=0
ok()   { printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
info() { printf '\033[1;36m[info]\033[0m %s\n' "$*"; }

echo "── Havit Fuxi-H3 fix — verification ──"

CARD=$(grep -iE 'FuxiH3|Fuxi-H3' /proc/asound/cards 2>/dev/null | head -1 | awk '{print $1}')
if [ -z "$CARD" ]; then
  info "dongle not detected right now — plug it in and re-run"
  exit 2
fi
info "ALSA card: $CARD"

# 1. hardware volume locked at 100%
VOL=$(amixer -c "$CARD" sget 'PCM',0 2>/dev/null | grep -oE '\[[0-9]+%\]' | tr -d '[]' | tr '\n' ' ')
if [ "$VOL" = "100% 100% " ]; then
  ok "hardware PCM,0 at 100% (both channels)"
else
  bad "hardware PCM,0 at: ${VOL:-n/a} (expected 100% 100%)"
fi

# 2. PCM,1 switch on (if present)
if amixer -c "$CARD" sget 'PCM',1 >/dev/null 2>&1; then
  SW=$(amixer -c "$CARD" sget 'PCM',1 | grep -oE '\[(on|off)\]' | head -1)
  if [ "$SW" = "[on]" ]; then
    ok "PCM,1 switch is on"
  else
    bad "PCM,1 switch is ${SW:-n/a} (expected [on])"
  fi
fi

# 3. WirePlumber soft-mixer props
SINK=$(pactl list sinks short 2>/dev/null | grep -i fuxi | awk '{print $2}')
if [ -n "$SINK" ]; then
  PROPS=$(pactl list sinks 2>/dev/null | grep -E 'alsa.soft-mixer|alsa.enable-hw-volume')
  if echo "$PROPS" | grep -q 'alsa.soft-mixer = "true"'; then
    ok "api.alsa.soft-mixer = true"
  else
    bad "api.alsa.soft-mixer NOT enabled — is the WirePlumber rule in place?"
  fi
  if echo "$PROPS" | grep -q 'alsa.enable-hw-volume = "false"'; then
    ok "api.alsa.enable-hw-volume = false"
  else
    bad "api.alsa.enable-hw-volume NOT disabled"
  fi
else
  info "Fuxi-H3 sink not in PipeWire yet (device suspended/absent?)"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1;32mAll %d check(s) passed — fix is active.\033[0m\n' "$PASS"
  exit 0
fi
printf '\033[1;31m%d check(s) failed.\033[0m\n' "$FAIL"
exit 1
