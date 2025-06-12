# IDB Calibration Tap Client (Simple)

A simple Rust client that uses `grpcurl` to tap calibration targets on iOS simulators.

## Prerequisites

- idb_companion running on port 10882
- iOS simulator with the calibration app running
- grpcurl installed (`brew install grpcurl`)

## Building

```bash
cd rust-client-simple
cargo build --release
```

## Running

```bash
cargo run
```

## How it works

This simpler version doesn't use the gRPC proto files directly. Instead, it:
1. Constructs JSON messages for the HID tap events
2. Uses the `grpcurl` command-line tool to send them to idb_companion
3. Taps the 5 calibration targets in sequence

This approach avoids the complexity of dealing with the proto file compilation issues while still providing a Rust-based solution.