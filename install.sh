#!/usr/bin/env bash
#
# Havit Fuxi-H3 — Linux volume fix installer
#
# Installs:
#   1. WirePlumber rule          -> ~/.config/wireplumber/wireplumber.conf.d/
#   2. ALSA helper script        -> /usr/local/bin/fuxi-h3-volume-fix.sh
#   3. udev rule                 -> /etc/udev/rules.d/99-fuxi-h3.rules
#   (optional --with-service) systemd user service -> re-applies after login
#
# Distros: Debian/Ubuntu (apt), Arch/CachyOS (pacman), Fedora (dnf), openSUSE (zypper)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
WITH_SERVICE=0

# ── helpers ────────────────────────────────────────────────────────────────
say()  { printf '\033[1;34m[fix ]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\033[1;36m[dry ]\033[0m %s\n' "$*"
    return 0
  fi
  "$@"
}

root() {
  if [ "$(id -u)" -eq 0 ]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

# ── CLI ────────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --with-service) WITH_SERVICE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./install.sh [--dry-run] [--with-service]

  --dry-run        preview what would be changed, without touching the system
  --with-service   also install a systemd user service that re-applies the
                   fix after login (race-safe: retries until the card is ready)
EOF
      exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

say "Havit Fuxi-H3 volume fix — installer"

# ── prerequisites ──────────────────────────────────────────────────────────
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
need_cmd grep
need_cmd awk

if command -v amixer >/dev/null 2>&1; then
  ok "alsa-utils present ($(amixer --version | head -1 | awk '{print $NF}'))"
else
  say "alsa-utils not found — installing..."
  if   command -v apt-get >/dev/null 2>&1; then root apt-get update -qq && root apt-get install -y alsa-utils
  elif command -v pacman  >/dev/null 2>&1; then root pacman -S --noconfirm --needed alsa-utils
  elif command -v dnf     >/dev/null 2>&1; then root dnf install -y alsa-utils
  elif command -v zypper  >/dev/null 2>&1; then root zypper install -y alsa-utils
  else die "unsupported distro — install alsa-utils manually and re-run"
  fi
  ok "alsa-utils installed"
fi

if ! command -v pactl >/dev/null 2>&1; then
  warn "pactl not found — install pipewire-utils (Debian) / libpipewire (Arch)."
  warn "The WirePlumber rule needs PipeWire to take effect; the udev/ALSA parts will still work."
fi

# ── 1. WirePlumber rule (user level) ───────────────────────────────────────
WP_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
run mkdir -p "$WP_DIR"
[ -f "$WP_DIR/fuxi-h3-fix.conf" ] && warn "wireplumber rule already exists — overwriting"
run install -m 644 "$REPO_DIR/wireplumber/fuxi-h3-fix.conf" "$WP_DIR/fuxi-h3-fix.conf"
ok "wireplumber rule -> $WP_DIR/fuxi-h3-fix.conf"

# ── 2. ALSA helper + udev rule (root level) ────────────────────────────────
root install -d /usr/local/bin /etc/udev/rules.d
root install -m 755 "$REPO_DIR/usr/local/bin/fuxi-h3-volume-fix.sh" /usr/local/bin/fuxi-h3-volume-fix.sh
root install -m 644 "$REPO_DIR/etc/udev/rules.d/99-fuxi-h3.rules" /etc/udev/rules.d/99-fuxi-h3.rules
ok "script        -> /usr/local/bin/fuxi-h3-volume-fix.sh"
ok "udev rule     -> /etc/udev/rules.d/99-fuxi-h3.rules"

root udevadm control --reload-rules
root udevadm trigger --subsystem-match=sound
ok "udev rules reloaded + sound subsystem re-triggered"

# ── 3. optional systemd user service ───────────────────────────────────────
if [ "$WITH_SERVICE" -eq 1 ]; then
  SD_DIR="$HOME/.config/systemd/user"
  run mkdir -p "$SD_DIR"
  run install -m 644 "$REPO_DIR/systemd/fuxi-h3-fix.service" "$SD_DIR/fuxi-h3-fix.service"
  run systemctl --user daemon-reload
  run systemctl --user enable --now fuxi-h3-fix.service
  ok "systemd user service enabled (re-applies fix after login)"
fi

# ── 4. restart audio stack + apply + verify ────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  say "dry-run finished — nothing was changed."
  exit 0
fi

say "restarting pipewire/wireplumber..."
for u in wireplumber pipewire pipewire-pulse; do
  systemctl --user restart "$u" 2>/dev/null || true
done
sleep 3

say "applying hardware volume fix now..."
/usr/local/bin/fuxi-h3-volume-fix.sh

say "verifying..."
"$REPO_DIR/check.sh"

say "done. Volume keys on the dongle itself are not covered by this fix —"
say "use PipeWire/desktop volume controls."
