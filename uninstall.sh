#!/usr/bin/env bash
#
# Havit Fuxi-H3 — uninstaller: removes every part of the fix.

set -euo pipefail

say() { printf '\033[1;34m[fix ]\033[0m %s\n' "$*"; }

root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

say "Removing Havit Fuxi-H3 fix..."

rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/fuxi-h3-fix.conf"
say "removed wireplumber rule"

root rm -f /usr/local/bin/fuxi-h3-volume-fix.sh
root rm -f /etc/udev/rules.d/99-fuxi-h3.rules
root udevadm control --reload-rules
say "removed script + udev rule, rules reloaded"

if [ -f "$HOME/.config/systemd/user/fuxi-h3-fix.service" ]; then
  systemctl --user disable --now fuxi-h3-fix.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/fuxi-h3-fix.service"
  systemctl --user daemon-reload 2>/dev/null || true
  say "removed systemd user service"
fi

if [ -f "$HOME/.config/systemd/user/fuxi-h3-keepalive.service" ]; then
  systemctl --user disable --now fuxi-h3-keepalive.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/fuxi-h3-keepalive.service"
  systemctl --user daemon-reload 2>/dev/null || true
  say "removed keep-alive service"
fi
root rm -f /usr/local/bin/fuxi-h3-keepalive.sh

say "Done. Restart the audio stack to revert to hardware volume:"
say "  systemctl --user restart wireplumber pipewire pipewire-pulse"
