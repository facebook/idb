# SimScope (experimental)

SimScope is a standalone macOS app for viewing and interacting with iOS Simulators. It is an experimental example of building an AppKit app with `FBSimulatorControl`: a live simulator display, accessibility inspector, input, recording, and a shared session with an agent.

The app and its agent protocol are experimental and may change without backward compatibility. SimScope has its own executable and control protocol; it is not an idb companion endpoint.

## Download and run

The public [CI workflow](https://github.com/facebook/idb/actions/workflows/ci.yml) builds an Apple Silicon app. Open a successful run and download the `SimScope-experimental-macos-arm64` artifact. Unzip the artifact, then unzip `SimScope-macos-arm64.zip` and move `SimScope.app` to Applications. GitHub requires sign-in to download workflow artifacts, which expire after 30 days.

Requirements:

- An Apple Silicon Mac running macOS 15 or newer.
- A full Xcode 26 or newer installation selected with `xcode-select`, with an iOS Simulator runtime installed.
- A booted iOS Simulator. SimScope attaches to an existing simulator.

Open `SimScope.app`. With several booted simulators, choose additional windows from **Simulator → Open Simulator**. To choose one at launch:

```sh
open -a SimScope --args --udid <UDID>
```

CI builds are ad-hoc signed, not Developer ID signed or notarized. macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. Whole-window recording also needs Screen Recording permission.

The download includes `simscope-remote`, `idb-repl`, the companion used by the Swift console, and the simulator helpers. No separate idb installation is needed. Apple's private simulator frameworks come from your Xcode installation.

## Build from source

From the repository root:

```sh
brew install xcodegen protobuf
./build.sh build simscope
open Build/Applications/SimScope.app
```

The downloadable archive is `Build/SimScope-macos-arm64.zip`. To check the assembled app after copying it away from the build tree:

```sh
SIMSCOPE_APP="$PWD/Build/Applications/SimScope.app" python3 Tools/SimScope/smoke_test.py -v
```

This checks signatures, bundled resources, framework loading and helper launch. It does not test window rendering, input or recording permissions.

## Using FBSimulatorControl

| App behavior | Starting point |
| --- | --- |
| Find simulator devices | `DeviceCatalog.swift`: `SimulatorControlBootstrap` |
| Attach to the display | `SimBackend.swift`: `Framebuffer.mainScreenSurface` |
| Display the surface | `SimulatorView.swift`: `IOSurface` and Core Animation |
| Read accessibility | `SimBackend.swift`: `simulator.uiAutomation` |
| Deliver input | `SimBackend.swift`: `simulator.lifecycle.connectToHID` |
| Inspect the tree | `AXTree.swift` and `TreeInspector.swift` |
| Share the session | `ControlChannel.swift`, `AgentDispatcher.swift`, `SimScopeProtocol/` |

The simulator's accessibility server must be enabled before the inspected app launches. If reads hang or the tree is missing, enable it and relaunch that app:

```sh
xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true
```

## Agent interface

SimScope keeps its own session protocol. Use the bundled CLI:

```sh
/Applications/SimScope.app/Contents/MacOS/simscope-remote status
/Applications/SimScope.app/Contents/MacOS/simscope-remote --help
```

See [AGENT.md](AGENT.md) for connecting, observing human actions, and sending actions with an intent caption.
