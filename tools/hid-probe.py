#!/usr/bin/env python3
"""
Havit Fuxi-H3 HID probe — reverse-engineering toolkit for the dongle's
vendor HID interface (Weltrend chip, interface 3, /dev/hidraw).

Modes:
  probe.py desc       dump + parse the HID report descriptor
  probe.py features   read all feature reports (settings the dongle exposes!)
  probe.py sniff N    timestamped capture of incoming reports for N seconds
                      (press buttons on the headset while sniffing)

Requires read/write access to the dongle's hidraw device (udev rule in this
repo grants MODE=0666; reload with `udevadm trigger --subsystem-match=hidraw`).
"""
import fcntl
import os
import select
import struct
import sys
import time

HIDIOCGRDESCSIZE = 0x80044801
HIDIOCGRDESC = 0x80044802
HIDIOCGFEATURE = 0xC0084806  # _IOWR('H', 0x06, struct hidraw_report_descriptor)

HID_ITEM = {
    0x04: ("Usage Page", "short"), 0x05: ("Usage Page", "long"),
    0x06: ("Usage Page", "long32"), 0x08: ("Usage", "short"),
    0x09: ("Usage", "short"), 0x0A: ("Usage", "long"),
    0x0B: ("Usage", "long32"),
    0x80: ("Input", "main"), 0x90: ("Output", "main"), 0xB0: ("Feature", "main"),
    0xA0: ("Collection", "main"), 0xC0: ("End Collection", "main"),
    0x34: ("Physical Minimum", "short"), 0x35: ("Physical Maximum", "short"),
    0x36: ("Physical Minimum", "long"), 0x37: ("Physical Maximum", "long"),
    0x38: ("Unit", "long"), 0x44: ("Logical Minimum", "short"),
    0x45: ("Logical Maximum", "short"), 0x46: ("Logical Minimum", "long"),
    0x47: ("Logical Maximum", "long"), 0x75: ("Report Size", "short"),
    0x76: ("Report Size", "long"), 0x95: ("Report Count", "short"),
    0x96: ("Report Count", "long"), 0x81: ("Input", "main"),
    0x91: ("Output", "main"), 0xB1: ("Feature", "main"),
    0x85: ("Report ID", "short"), 0x19: ("Usage Minimum", "short"),
    0x29: ("Usage Maximum", "short"), 0x1A: ("Usage Minimum", "long"),
    0x2A: ("Usage Maximum", "long"),
}


def find_hidraw():
    for i in range(16):
        h = f"/dev/hidraw{i}"
        if not os.path.exists(h):
            continue
        try:
            target = os.readlink(f"/sys/class/hidraw/hidraw{i}")
        except OSError:
            continue
        if "040B:0897" in target or "040b:0897" in target:
            return h
    return None


def report_descriptor(fd):
    buf = struct.pack("H", 0)
    fcntl.ioctl(fd, HIDIOCGRDESCSIZE, buf)
    size = struct.unpack("H", buf)[0]
    buf = struct.pack("I", size) + bytes(4096)
    fcntl.ioctl(fd, HIDIOCGRDESC, buf)
    size = struct.unpack_from("I", buf)[0]
    return buf[4:4 + size]


def parse_descriptor(rdesc):
    """Lightweight HID descriptor walker: report IDs, usage pages, field sizes."""
    print(f"report descriptor: {len(rdesc)} bytes")
    print(f"hex: {rdesc.hex()}\n")
    i, report_id, page = 0, 0, 0
    while i < len(rdesc):
        b = rdesc[i]
        kind = b & 0xFC
        size = b & 0x03
        if size == 3:
            size = 4
        name, typ = HID_ITEM.get(kind, (f"item 0x{b:02x}", "?"))
        i += 1
        val = rdesc[i:i + size]
        i += size
        v = int.from_bytes(val, "little") if val else 0
        if kind == 0x04:
            page = v
            print(f"  usage page = 0x{page:04x}")
        elif kind == 0x85:
            report_id = v
            print(f"  [report ID {report_id}]")
        elif typ == "main":
            flags = v
            bits = flags & 0x1F
            print(f"  {name:8s} rid={report_id or 1:2d} size={bits:3d} bits"
                  f"  {'(const)' if flags & 0x01 else ''}"
                  f" {'(var)' if flags & 0x02 else ''}"
                  f" {'(abs)' if flags & 0x04 else '(rel)'}"
                  f" page=0x{page:04x}")
        elif name in ("Usage Page", "Usage", "Report Size", "Report Count",
                      "Logical Min", "Logical Max"):
            print(f"  {name:12s} = {v}")


def read_feature(fd, report_id, length=64):
    buf = bytes([report_id]) + bytes(length)
    try:
        fcntl.ioctl(fd, HIDIOCGFEATURE, buf)
    except OSError as e:
        return None, str(e)
    return buf[:length + 1], None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    mode = sys.argv[1]

    hid = find_hidraw()
    if not hid:
        print("Fuxi-H3 hidraw device not found — dongle plugged in?")
        sys.exit(2)
    try:
        fd = os.open(hid, os.O_RDWR)
    except PermissionError:
        print(f"{hid}: permission denied.\n"
              "Install the udev rule from this repo and run:\n"
              "  sudo udevadm control --reload-rules\n"
              "  sudo udevadm trigger --subsystem-match=hidraw")
        sys.exit(3)
    print(f"device: {hid}")

    if mode == "desc":
        parse_descriptor(report_descriptor(fd))
    elif mode == "features":
        # try every plausible report ID
        rdesc = report_descriptor(fd)
        ids = {1}
        for i in range(len(rdesc)):
            if rdesc[i] == 0x85:
                ids.add(rdesc[i + 1])
        print(f"probing feature reports for IDs {sorted(ids)}...")
        for rid in sorted(ids):
            for length in (16, 32, 64):
                data, err = read_feature(fd, rid, length)
                if data is not None:
                    print(f"  feature ID {rid} ({length}B): {data.hex()}")
                    break
            else:
                print(f"  feature ID {rid}: no response ({err})")
    elif mode == "sniff":
        seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        print(f"sniffing {seconds}s — press buttons on the headset now "
              "(Ctrl+C to stop early)")
        end = time.time() + seconds
        buf = b""
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.5)
            if not r:
                continue
            try:
                chunk = os.read(fd, 256)
            except OSError:
                break
            if not chunk:
                continue
            buf += chunk
            while len(buf) >= 1:
                # hidraw reports are size-prefixed
                n = buf[0]
                if len(buf) < n + 1:
                    break
                report = buf[1:n + 1]
                buf = buf[n + 1:]
                print(f"  t={time.time() % 1000:7.3f}  {report.hex(' ')}")
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
