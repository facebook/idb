# Device Hub compatibility matrix

Device Hub support must be validated against the selected Xcode and the
targeted simulator runtime independently. Selecting Xcode 27 does not imply
that an iOS 26 simulator should use the iOS 27 accessibility bootstrap or HID
transport.

## Required matrix

Record evidence for each supported cell:

- Xcode 26 with an iOS 26 simulator, hosted by Simulator.app.
- Xcode 27 with an iOS 26 simulator.
- Xcode 27 with an iOS 27 simulator, hosted by Device Hub while Simulator.app
  is not running.

Capture the environment before testing:

```bash
./verify_device_hub_environment.sh \
  --developer-dir /Applications/Xcode.app/Contents/Developer \
  --udid SIMULATOR_UDID
```

Save the JSON output with the test result. It identifies the exact Xcode and
runtime builds and prevents a host-toolchain result from being attributed to a
different target runtime.

## Behavior checks

For every matrix cell, exercise the release-shaped FBSimulatorControl
frameworks rather than a source-linked test build:

1. Resolve the booted simulator by UDID.
2. Fetch and serialize the frontmost accessibility hierarchy with nested
   output and the default key set.
3. Repeat the hierarchy fetch with `traits` explicitly requested.
4. Query one element at a point.
5. Send a tap, swipe, long press, two-finger touch, keyboard event, and Home
   button event.
6. Reboot the simulator and repeat one accessibility fetch and tap to expose
   stale process-scoped state.

The Xcode 27/iOS 27 cell additionally requires:

- Device Hub is running.
- Simulator.app is not running.
- Device Hub Resize Mode is disabled. Apple simulator services can report
  successful HID sends while dropping touches when Resize Mode is enabled.

## Acceptance

- A hierarchy fetch returns at least one root and one descendant.
- Requesting `traits` does not collapse an otherwise valid hierarchy.
- Point lookup returns a bounded element rather than a full-screen transient
  fallback.
- Every HID action is observed in the simulator exactly once.
- A simulator reboot does not require restarting the host process.
- The same framework payload is used for every matrix cell.
