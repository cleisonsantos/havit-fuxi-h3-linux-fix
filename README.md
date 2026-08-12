# Havit Fuxi-H3 — Linux volume fix

Fixes a bug where the Havit Fuxi-H3 2.4 GHz wireless headset (USB dongle `040b:0897`)
mutes **one channel** whenever volume is lowered below 100% on Linux.

| | |
|---|---|
| **Vendor/Product** | `040b:0897` (XiiSound Technology Corporation) |
| **Driver** | `snd_usb_audio` |
| **Affects** | Any Linux with PipeWire + WirePlumber (Debian, Arch/CachyOS, Fedora, …) |
| **Tested on** | Debian 12 (WirePlumber 0.5.15, PipeWire 1.6.8) · Arch/CachyOS (WP 0.4 / 0.5) |

## The problem

The dongle exposes two PCM controls to ALSA with an absurdly tiny dB range
(`0.00 dB` – `0.39 dB`), and the hardware treats *any* value below 100% as
**mute on one channel**. So on stock Linux, lowering the volume below 100%
silences the left *or* right side. The real volume lives in the dongle's
firmware and can't be controlled directly.

## The fix — 3 parts

1. **WirePlumber rule** — forces a software mixer (PipeWire handles volume),
   locking the hardware at 100%.
2. **ALSA helper script** — forces the hardware PCM controls to 100%
   (runs on hotplug via udev, and optionally at login via a systemd user service).
3. **udev rule** — runs the helper whenever the dongle is plugged in.

## Requirements

- PipeWire **with WirePlumber** (default on Debian 12+, Arch, CachyOS, Fedora…)
- `alsa-utils` (`amixer`) — the installer installs it automatically
- `sudo` access

## Install

```bash
git clone https://github.com/cleisonsantos/havit-fuxi-h3-linux-fix.git
cd havit-fuxi-h3-linux-fix
./install.sh                # optional: --with-service for the login re-apply
```

`install.sh` detects your distro (`apt` / `pacman` / `dnf` / `zypper`), installs
`alsa-utils` if missing, copies the three parts to the right places, reloads
udev, restarts PipeWire/WirePlumber, applies the fix immediately and runs the
verifier. Use `--dry-run` to preview without changing anything.

```bash
./install.sh --dry-run      # preview
./install.sh --with-service # + systemd user service (re-apply after login, race-safe)
```

## Verify

```bash
./check.sh
```

Expected output (when the dongle is plugged in):

```
[PASS] hardware PCM at 100% (both channels)
[PASS] PCM,1 switch is on
[PASS] api.alsa.soft-mixer = true
[PASS] api.alsa.enable-hw-volume = false
```

Manual check:

```bash
pactl list sinks | grep -E "soft-mixer|enable-hw-volume"
#   api.alsa.soft-mixer = "true"
#   api.alsa.enable-hw-volume = "false"

amixer -c "$(grep -i fuxi /proc/asound/cards | awk '{print $1}')" sget 'PCM',0
#   Front Left:  Playback 100 [100%] [0.39dB] [on]
#   Front Right: Playback 100 [100%] [0.39dB] [on]
```

## Uninstall

```bash
./uninstall.sh
```

## How it works

```
 ┌──────────────────────────── PipeWire ────────────────────────────┐
 │  app volume  ──►  software mixer (soft-mixer)  ──►  ALSA card    │
 │  (real volume,   WirePlumber rule sets                           │
 │   both channels  api.alsa.soft-mixer = true)                     │
 │   attenuated)                                      HW locked at  │
 │                                                     100%         │
 └──────────────────────────────────────────────────────────────────┘
```

- `wireplumber/fuxi-h3-fix.conf` → `~/.config/wireplumber/wireplumber.conf.d/`
  (user-level, works on WirePlumber 0.4 **and** 0.5 — `monitor.alsa.rules` +
  `update-props`)
- `usr/local/bin/fuxi-h3-volume-fix.sh` → `/usr/local/bin/` (idempotent; finds the
  ALSA card by name, card number may vary per machine)
- `etc/udev/rules.d/99-fuxi-h3.rules` → `/etc/udev/rules.d/` (fires on hotplug)
- `systemd/fuxi-h3-fix.service` → user service, optional (`--with-service`).
  Sets `FUXI_H3_RETRY=1` so the script exits non-zero when the card isn't ready
  yet and `Restart=on-failure` + `RestartSec=3` retry until it is — this avoids
  the boot/login race condition.

## Troubleshooting

- **Card number differs** (`1`, `2`, …): irrelevant — the script greps
  `/proc/asound/cards` for `FuxiH3`.
- **`PCM,1` says "Invalid command"**: on some firmwares `PCM,1` is a mute
  *switch only* (no volume). The script handles both variants (`100%` and `on`).
- **Volume keys (hardware) still mute one side**: the dongle's onboard volume
  keys bypass the OS. Keep using PipeWire/desktop volume controls.
- **`systemctl --user restart wireplumber` fails**: ensure the WirePlumber
  service name matches your distro (`wireplumber.service` is standard).

## Files

```
├── install.sh                    # distro-aware installer
├── uninstall.sh                  # removes everything
├── check.sh                      # verification
├── wireplumber/fuxi-h3-fix.conf  # soft-mixer rule (WP 0.4/0.5)
├── usr/local/bin/fuxi-h3-volume-fix.sh
├── etc/udev/rules.d/99-fuxi-h3.rules
└── systemd/fuxi-h3-fix.service   # optional user service
```

---

## Português (resumo)

O dongle do headset Havit Fuxi-H3 (`040b:0897`) muta um canal quando o volume
fica abaixo de 100%. A solução trava o volume do hardware em 100% e usa o
soft-mixer do PipeWire (regra do WirePlumber) para o volume real. Instale com
`./install.sh` (dependências detectadas automaticamente: Debian/Ubuntu, Arch,
CachyOS, Fedora, openSUSE).

## License

MIT
