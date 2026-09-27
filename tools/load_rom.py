#!/usr/bin/env python3
"""Send an SMS ROM to the ULX3S serial loader."""

import argparse
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is required: python3 -m pip install pyserial")

BAUD = 921600
MAX_LEN = 4 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser(
        description="Load an SMS ROM over the ULX3S USB serial port"
    )
    parser.add_argument("port", help="Serial port, for example /dev/cu.usbserial-XXXX")
    parser.add_argument("rom", help="Path to a .sms ROM")
    args = parser.parse_args()

    with open(args.rom, "rb") as rom_file:
        data = rom_file.read()
    if len(data) == 0:
        sys.exit(f"{args.rom} is empty")
    if len(data) > MAX_LEN:
        sys.exit(f"{args.rom} is {len(data)} bytes; the loader accepts at most {MAX_LEN}")

    checksum = 0
    for byte in data:
        checksum ^= byte

    frame = b"L" + len(data).to_bytes(4, "big") + data + bytes([checksum])
    # One byte is 10 bit times. Leave room for the FPGA to answer after the last byte.
    ack_timeout = max(2.0, (len(frame) * 10) / BAUD + 2.0)

    with serial.Serial(args.port, BAUD, timeout=0.05) as ser:
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if ser.read(1) == b"R":
                break
        else:
            sys.exit("timed out waiting for the FPGA loader (press the power button and try again)")

        sent = 0
        chunk = 4096
        while sent < len(frame):
            written = ser.write(frame[sent:sent + chunk])
            if not written:
                sys.exit("serial write failed")
            sent += written
            print(f"\r{min(100, sent * 100 // len(frame)):3d}%", end="", flush=True)
        ser.flush()
        print()

        deadline = time.monotonic() + ack_timeout
        while time.monotonic() < deadline:
            reply = ser.read(1)
            if reply == b"K":
                print(f"loaded {len(data)} bytes")
                return
            if reply == b"E":
                sys.exit("FPGA rejected the transfer")
        sys.exit("timed out waiting for the FPGA to acknowledge the ROM")


if __name__ == "__main__":
    main()
