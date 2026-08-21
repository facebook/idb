# FBSimulatorControl

A macOS library for managing, booting and interacting with multiple iOS Simulators simultaneously.

`FBSimulatorControl` is primarily an implementation detail of `idb`: the `idb_companion` is its main consumer, and for most automation `idb` is the better choice. The framework is also built to be used directly, for two main reasons:

- **Building native macOS applications.** A macOS application can link the framework and control Simulators in-process, with no separate client, gRPC hop, or companion lifecycle to manage. That includes [building a new simulator app](#beyond-apples-tools) that renders and drives the screen itself. [qalti](https://github.com/qalti/qalti), for example, embeds the idb frameworks directly inside a macOS testing product.
- **Finer-grained control.** The framework exposes more than the `idb` cli surfaces, such as direct framebuffer access, live video streaming, HID event synthesis and boot configuration. It also lets a consumer combine that functionality in ways the cli deliberately simplifies. [serve-sim](https://github.com/EvanBacon/serve-sim) ported the framework's host-side accessibility reading into its own server.

The trade-off is stability. The `idb` cli and its gRPC interface are the project's compatibility boundary and change conservatively. The frameworks are the implementation behind that boundary, so their APIs change more freely. A direct consumer should expect to track those changes when updating.

## Features

- Boots multiple Simulators concurrently on the same host, isolated in custom 'Device Sets'.
- Boots iOS Simulators across a range of Xcode and iOS Versions.
- Runs independently of Xcode and `xcodebuild` without requiring embedding in a Graphical User Interface. Uses whatever Xcode toolchain is defined by `xcode-select`.
- Exposes a broad range of functionality that is available in `simctl` and Xcode.
- Implements additional functionality not available in `simctl` including hardware encoded video streaming, file manipulation, accessibility fetching, direct input event injection and more.
- No external dependencies.
- A mix of Objective-C and Swift, transitioning to pure Swift over time; the API is usable from both languages.

## About

The original use-case for `FBSimulatorControl` was to boot multiple Simulators on the same host, before this was officially supported in Xcode.

`FBSimulatorControl` works by linking with the private `CoreSimulator` and `SimulatorKit` frameworks that are installed as part of Xcode. Doing this allows  `FBSimulatorControl` to talk directly to the same APIs that Xcode and `simctl` use. `FBSimulatorControl` also adds features that aren't present in Xcode or the iOS Simulator, such as accessibility fetching.

## Installation

The homebrew installation is derived from [the `build.sh`](../build.sh) script in the root of the repository. You can build `FBSimulatorControl` on its own with: `./build.sh build FBSimulatorControl` (or build every framework with `./build.sh build frameworks`).

The `FBSimulatorControl.xcodeproj` builds the `FBSimulatorControl.framework` and the `FBSimulatorControlTests.xctest` bundles. The project file is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (run `./build.sh generate`), so it is not checked into the repo.

Once you build the `FBSimulatorControl.framework`, it can be linked like any other 3rd-party Framework for your project:
- Add `FBSimulatorControl.framework` to the [Target's 'Link Binary With Libraries' build phase](Documentation/link_binary_with_libraries.png).
- Ensure that `FBSimulatorControl` is copied into the Target's bundle (if your Target is an Application or Framework) or a path relative to the Executable if your project does not have a bundle.

## Usage

In order to support different Xcode versions and system environments, `FBSimulatorControl` weakly links against Xcode's Private Frameworks and loads these Frameworks when they are needed. `FBSimulatorControl` will link against the version of Xcode that you have set with [`xcode-select`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcode-select.1.html). It is not recommended to run against multiple versions of Xcode on the same host as `CoreSimulator` has user-level daemons that cannot run against multiple versions of Xcode concurrently.

Since the Frameworks upon which `FBSimulatorControl` depends are loaded lazily, they must be loaded before the Framework is functional. However, you do not have to do this manually as any of the `FBSimulatorControl` functionality that has this dependency will load these Private Frameworks when they are used for the first time.

[The tests](FBSimulatorControlTests/Tests) should provide you with some basic guidance for using the API, and the `idb_companion` in this repository is a full-featured consumer of it.

For a high level overview:
- `FBSimulatorControl` is the Principal Class. It is the first object that you should create, with `FBSimulatorControl.withConfiguration(_:)` (`+[FBSimulatorControl withConfiguration:error:]` from Objective-C). It creates a `FBSimulatorSet` upon creation, exposed as `set`.
- `FBSimulatorSet` wraps `SimDeviceSet` and provides a resilient CRUD API for Deleting, Creating and Erasing Simulators.
- `FBSimulator` is a reference type that represents an individual Simulator. It has a number of convenience methods for accessing information about a Simulator. Many of the possible actions you can perform on a Simulator are present on instances of this class.
- Configuration objects: `FBApplicationLaunchConfiguration`, `FBSimulatorControlConfiguration`, `FBSimulatorConfiguration` & `FBSimulatorBootConfiguration`.


## Beyond Apple's tools

`FBSimulatorControl` supported "Multisim" (booting many Simulators concurrently on one host, headlessly, isolated in custom device sets) years before Xcode and `simctl` did. Apple's tools now provide all of this, so it is no longer a reason to pick the framework.

Even where the functionality overlaps with `simctl`, the framework provides it differently. `simctl` launches a process per operation: every call pays a process launch and a fresh binding to `CoreSimulator` before doing any work. `FBSimulatorControl` links `CoreSimulator` and `SimulatorKit` directly and provides the same operations as an in-process API, over a connection that is bound once and reused. This makes the framework practical to embed in an application instead of shelling out to `simctl`. It is also why individual operations in the `idb_companion` are fast: the companion binds `CoreSimulator` at startup, not once per command.

The framework also provides functionality that has no equivalent in `simctl`, `xcodebuild` or the host app. Most of it is built on protocols and services that Apple's own tools use internally but do not expose:

- **Live screen access.** A booted Simulator's screen is available to the linking process as an `IOSurface`-backed framebuffer. The framework turns this into screenshots, video files, or live streams of hardware-encoded H.264, MJPEG, or raw frames. `simctl` can only record a video file after the fact; it cannot stream, and it cannot give your process access to the GPU-resident surface.
- **Input synthesis.** Touch, keyboard and hardware-button events are delivered over the Simulator's own HID services: the reverse-engineered Indigo mach protocol, or the `dtuhidd` XPC path on newer Xcodes. Device orientation is delivered over GSEvent ("Purple"), and shake via Darwin notifications. Apple's only supported route to synthesized input is an XCUITest bundle.
- **Accessibility reading.** The framework reads the full element hierarchy of the frontmost application without a test bundle, either through host-side translation or in-guest at XCUITest fidelity via the bundled `SimulatorFrameworkBridge` helper. This is described in [the accessibility documentation](https://www.fbidb.io/docs/idb/accessibility).
- **In-guest state injection.** `SimulatorFrameworkBridge` runs inside the booted Simulator and can modify state that no `simctl` verb reaches, such as overwriting the contacts database or clearing the photo library.

Combined, live screen access, input synthesis and accessibility reading are enough to build a new "simulator app": a macOS application or remote-streaming service that presents and drives Simulators with its own UI and transport, the way `Simulator.app` does.

Continuous, interactive work like this is where the in-process connection matters, and where driving `idb` from a separate process is not sufficient:

- **Frame delivery.** The `idb` cli provides an encoded byte stream. In-process, you get the `IOSurface` itself, GPU-resident and zero-copy, and can feed it to your own view, encoder or pixel analysis at the display's rate.
- **Live input.** The cli synthesizes discrete gestures that are described up front, such as a tap or a swipe. An app following a real pointer needs a persistent HID connection that streams touch positions as they happen, at input-device rates.
- **Long-lived state.** Every cli invocation pays client startup and an RPC round trip, and re-resolves its target. A tight read-decide-act loop is better served by long-lived framework objects that keep the boot, the HID connection and the accessibility session alive between calls.

## Contributing
See the [CONTRIBUTING](CONTRIBUTING) file for how to help out. There's plenty to work on the issues!
