# IDB Calibration Tap Client

A Rust client for tapping calibration targets on iOS simulators using idb_companion's gRPC interface.

## Prerequisites

- idb_companion running on port 10882
- iOS simulator with the calibration app running

## Building

```bash
cd rust-client
cargo build --release
```

## Running

```bash
cargo run
```

## How it works

The client connects to idb_companion's gRPC service and sends HID (Human Interface Device) events to simulate taps on the screen. It taps 5 calibration targets in sequence:

1. Top-left (20%, 20%)
2. Top-right (80%, 20%)
3. Center (50%, 60%)
4. Bottom-left (20%, 80%)
5. Bottom-right (80%, 80%)

Each tap consists of:
- A touch DOWN event at the target coordinates
- A 50ms delay (to simulate human touch duration)
- A touch UP event at the same coordinates
- A 1 second delay before the next tap

## Customization

The target coordinates are calculated based on iPhone 16 Pro Max screen dimensions (430x932 points). If you're using a different device, you may need to adjust the coordinates in `main.rs`.

## Protocol

The client uses the idb.proto gRPC protocol to communicate with idb_companion. The HID events are sent as a bidirectional stream to the `hid` RPC method.