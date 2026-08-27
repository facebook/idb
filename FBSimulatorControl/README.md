# FBSimulatorControl

A macOS library for managing, booting and interacting with multiple iOS Simulators simultaneously.

`FBSimulatorControl` is primarily an implementation detail of `idb`: the `idb_companion` is its main consumer, and for most automation `idb` is the better choice. The framework is also built to be used directly, for two main reasons:

- **Building native macOS applications.** A macOS application can link the framework and control Simulators in-process, with no separate client, gRPC hop, or companion lifecycle to manage. That includes [building a new simulator app](#functionality-beyond-apples-tools) that renders and drives the screen itself. [qalti](https://github.com/qalti/qalti), for example, embeds the idb frameworks directly inside a macOS testing product.
- **Finer-grained control.** The framework exposes more than the `idb` cli surfaces, such as direct framebuffer access, live video streaming, HID event synthesis and boot configuration. It also lets a consumer combine that functionality in ways the cli deliberately simplifies. [serve-sim](https://github.com/EvanBacon/serve-sim) ported the framework's host-side accessibility reading into its own server.

The trade-off is stability. The `idb` cli and its gRPC interface are the project's compatibility boundary and change conservatively. The frameworks are the implementation behind that boundary, so their APIs change more freely. A direct consumer should expect to track those changes when updating.

## Features

- Boots multiple Simulators concurrently on the same host, isolated in custom 'Device Sets'.
- Boots iOS Simulators across a range of Xcode and iOS Versions.
- Runs independently of Xcode and `xcodebuild` without requiring embedding in a Graphical User Interface. Uses whatever Xcode toolchain is defined by `xcode-select`.
- Exposes a broad range of functionality that is available in `simctl` and Xcode.
- Implements additional functionality not available in `simctl` including hardware encoded video streaming, file manipulation, accessibility fetching, direct input event injection and more.
- No external dependencies.
- A Swift framework. What Objective-C remains is an implementation detail of reaching Apple's private frameworks, not part of the API.

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
- `FBSimulatorControl` is the Principal Class. It is the first object that you should create, with `FBSimulatorControl.withConfiguration(_:)`. It creates a `FBSimulatorSet` upon creation, exposed as `set`.
- `FBSimulatorSet` wraps `SimDeviceSet` and provides a resilient CRUD API for Deleting, Creating and Erasing Simulators.
- `FBSimulator` is a reference type that represents an individual Simulator. It has a number of convenience methods for accessing information about a Simulator. Many of the possible actions you can perform on a Simulator are present on instances of this class.
- Configuration values: `FBApplicationLaunchConfiguration`, `FBSimulatorControlConfiguration`, `FBSimulatorConfiguration` & `FBSimulatorBootConfiguration`. The last three are structs.


## Functionality beyond Apple's tools

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

## How Simulator control works

The framework is built on the private frameworks and services that Apple's own tools use. The sections below describe what each one is and how `FBSimulatorControl` drives it.

### `CoreSimulator.framework`

`CoreSimulator` is the Private Framework that is the interface for most Simulator related functionality on macOS. In previous Xcode versions, `CoreSimulator` was bundled inside of Xcode, but it is now installed at the System level just like `MobileDevice.framework`. It may be upgraded to a newer version as part of the install process of Xcode itself.

`CoreSimulator` is used by Xcode and `simctl` as the Framework used to manipulate Simulators. It has Objective-C classes representing a set of Simulators within a directory (`SimDeviceSet` wrapped by `FBSimulatorSet`) and an individual iOS Simulator (`SimDevice`, wrapped by `FBSimulator`). There is also a Class that behaves a lot like an "entrypoint" to the Framework in `SimServiceContext`, this performs initialization of external services and is aware of the various configurations of Simulators that are available.

### `simctl`

`simctl` is a CLI that exposes iOS Simulator functionality by linking and using `CoreSimulator`. This binary is bundled inside of Xcode, and typically addressed via the `xcrun` command. `xcrun` is a trampoline that locates binaries bundled within Xcode, using the value defined in `xcode-select`.

The overwhelming majority of Simulator functionality is not implemented in `simctl`, it is implemented within `CoreSimulator` with `simctl` providing an accessible way of using this functionality. Having this behaviour implemented at the Framework level means that `Simulator.app` and `simctl` behave consistently, as they share the same implementation.
### `CoreSimulatorService`

`CoreSimulatorService` is a user-level daemon that is bootstrapped by any usage of `SimServiceContext`, effectively any usage of iOS Simulators will cause this service to be created and launched. This is an XPC service contained within the `CoreSimulator.framework` bundle. This service is responsible for starting and managing Simulators.

When using `CoreSimulator` as a client Framework it will transparently communicate with `CoreSimulatorService`. The overwhelming majority of `CoreSimulator` APIs that do meaningful work are performing IO to `CoreSimulatorService`, though the asynchronous nature of this work isn't completely consistent. Some `CoreSimulator` APIs (for instance those associated with [launching an iOS Application](https://github.com/facebook/idb/blob/main/PrivateHeaders/CoreSimulator/SimDevice.h)) do have asynchronous methods, but others (such as the [instantiation of a `SimServiceContext`](https://github.com/facebook/idb/blob/main/PrivateHeaders/CoreSimulator/SimServiceContext.h)) do not. `CoreSimulatorService` still gets much of its implementation from `CoreSimulator.framework`, touching different areas of the API.

Having the "work" of iOS Simulators performed within a shared user daemon is likely due to the need to synchronize and consolidate state. The service is also an effective caching mechanism for runtime and device profiles. There are a few downsides to this approach. Firstly, `CoreSimulatorService` is effectively a single point of failure. If `CoreSimulatorService` becomes stuck, or a client of `CoreSimulator` exhibits pathological behaviour, then all iOS Simulator functionality on a given host will fail. iOS Simulator functionality will effectively halt until `CoreSimulatorService` restarts, either by the hung `CoreSimulatorService` terminating and restarting or via reboot.

Secondly, the lifecycle of `CoreSimulatorService` is tied to that of the selected `Xcode`. This means that different versions of Xcode cannot be used concurrently on the same host; `CoreSimulatorService` can only be aware of a single Xcode at any point in time. Switching Xcodes and fetching a new `CoreSimulatorService` (for instance via a `simctl` command) will cause `CoreSimulatorService` to restart, disconnecting existing clients and killing booted Simulators.

### `SimRuntime`

An iOS Simulator Runtime is all of the required components for running an iOS Simulator of a given iOS version. This is a bundle, where the contents closely match the makeup of the files on disk on a physical device. This includes binaries that are compiled for the host architecture (x86_64 in the case of Intel Macs, ARM64 in the case of ARM based Macs) as well as Frameworks. The Frameworks within a SimRuntime match those of iOS, instead of those of the macOS host. There are often subtle differences in the iOS and macOS APIs, even within the same Framework. A single `SimRuntime` represents a single iOS version.

Each version of Xcode is bundled with `SimRuntime`s for the most recent iOS version that is relevant for the Xcode version across iOS, tvOS and watchOS. However, additional iOS Versions can be supported on a given version of Xcode via the "Components" section within `Xcode.app`. These bundles are then installed into `/Library/Developer/CoreSimulator/Profiles/Runtimes` on the host system. Runtime bundles are backwards, but not forwards compatible. For example, Xcode 11 has support for iOS 13 (the latest iOS version associated with this Xcode version) and earlier versions of iOS, but not for iOS 14.

### `launchd_sim`

iOS, like macOS has `launchd` as its "root process" (often PID 1). However, iOS Simulators have their own version of `launchd` as a root process. This `launchd_sim` is effectively the "root process" of the iOS Simulator runtime, but not of the macOS host. This `launchd_sim` is required by the Simulator OS in order to launch Applications, manage services etc. Each launched iOS Simulator has its own `launchd_sim` process, launched from the `launchd_sim` within the `SimRuntime`. This also means that processes within this nested `launchd` will only see the processes of the iOS Simulator, rather than all of those of the entire host (including other iOS Simulators running on the same host).

This `launchd_sim` can be interrogated the same as the `launchd` of the host, provided that the `launchctl` called is spawned within the `launchd_sim` of the iOS Simulator.

### Device Sets

A Device Set is a directory that contains a number of created iOS Simulators. The "Default Device Set" is located at `~/Library/Developer/CoreSimulator/Devices`, this is the device set that is used by `Xcode.app`.

Custom device sets can be placed at any location on disk. This is useful for isolating the filesystems of created iOS Simulators from each other. For instance, if there are independent processes managing iOS Simulators on the same host it can be worthwhile having each of these processes manage their own device sets to prevent data races.

There is also an `XCTestDevices` directory at `~/Library/Developer/XCTestDevices`. This is the set of Simulators that are used by `xcodebuild`, distinct from the user interface. This means that `xcodebuild` can manage and use it's own set of iOS Simulators, independent of the Xcode UI. This may exist for a similar reasons to why custom device sets are practical for automation scenarios. It would also be a confusing user experience if an iOS Simulator that was being used within `xcodebuild` was using an iOS Simulator that a user was using via Xcode when running UI Tests.

### `Simulator.app`

This is the "Simulator" Application with which most developers will be familiar with. This Application effectively mirrors the state of launched iOS Simulators within `CoreSimulatorService`. It is not an essential part of booting and managing iOS Simulators; iOS Simulators can be booted and used without a `Simulator.app` launched for it. This makes using Simulators more practical in automation scenarios where a running macOS Application representing the iOS Simulator is not important or even desirable.

The Simulator Application will default to showing all iOS Simulators that are within the "Default Device Set". This means that booted iOS Simulators within "Custom Device Sets" will not be displayed within `Simulator.app`.

The functionality within this Application is largely implemented within `CoreSimulator.framework` and `SimulatorKit.framework`, with the UI implemented directly within the application itself.

### `DeviceHub.app` (Xcode 27 and later)

From Xcode 27, the host application is the CoreDevice-based `DeviceHub.app` rather than `Simulator.app`. `FBSimulatorControl` launches whichever host app the active Xcode ships. The behaviour above carries over: `DeviceHub.app` also displays only the default device set, so Simulators in a custom device set (for example, the clones Xcode creates for parallel testing) are not shown.

A Simulator presented in either host app has its framebuffer consumed by that app's process, so the framebuffer is not available to a process linking `FBSimulatorControl`. Boot without the host app when you need the screen.

### Framebuffers via `IOSurface`

The screen from an iOS Simulator is rendered, regardless of whether there is a `Simulator.app` presenting it in a window. An iOS Simulator can be launched independently of `Simulator.app`, since Simulators are kept alive by `CoreSimulatorService`.

In order for other Applications (mainly `Simulator.app`, but also for video recording within `simctl`) to get the iOS Simulator's Framebuffer for rendering, `CoreSimulator` can access the `IOSurface` of the screen of an iOS Simulator. A Simulator can have many screens, for instance when Simulating CarPlay and the main screen at the same time.

An `IOSurface` is an object that wraps a Framebuffer, with the contents of the Framebuffer being located within GPU memory. This `IOSurface` can be read and inspected across process boundaries. `Simulator.app` uses this `IOSurface` as the backing Framebuffer for its view of an iOS Simulator.

`IOSurface` objects are also easily convertible to "Pixel Buffer" types that are used in video encoding, which [`FBSimulatorVideoStream`](https://github.com/facebook/idb/blob/main/FBSimulatorControl/Framebuffer/FBSimulatorVideoStream.swift) takes advantage of. This allows `FBSimulatorControl` to implement video encoding of an iOS Simulator's Framebuffer in a way that avoids large copies of bitmap framebuffers on a per-frame basis.

### HID: `IndigoHID` and `DTUHID`

"Indigo" is a service present in the iOS Simulator that is used inside `Simulator.app` to synthesize "Input Events" that are understood within the iOS Simulator. This service is how clicking on the UI of the `Simulator.app` translates into touches within the iOS Simulator.

This uses "mach" IPC, where data structures are sent over a channel using `mach_msg_send`. These data structures are defined through the "Mach Interface Generator", which get compiled out of the `Simulator.app` binary. As such, `FBSimulatorControl`'s understanding of the layout and values in these data structures [are understood through reverse engineering](https://github.com/facebook/idb/blob/main/PrivateHeaders/SimulatorApp/Indigo.h).

The reverse engineering of this protocol allows `FBSimulatorControl` to expose APIs that send touch events directly to the iOS Simulator without using Accessibility APIs in a UI Test. The combination of video streams and APIs for sending input events allows for the building of applications that expose a remote iOS Simulator.

Newer Xcode versions introduce a second event path: a `dtuhidd` daemon inside the Simulator, which receives events as XPC dictionaries rather than reverse-engineered mach structures. On these runtimes the guest moves some of its legacy HID services to `dtuhidd`, so `FBSimulatorControl` implements HID delivery behind a pluggable transport ([`FBSimulatorHID`](https://github.com/facebook/idb/blob/main/FBSimulatorControl/HID/FBSimulatorHID.swift)). The Indigo transport remains the default where it works, and the [DTUHID transport](https://github.com/facebook/idb/blob/main/FBSimulatorControl/HID/FBSimulatorDTUHIDTransport.swift) is used where the runtime requires it, negotiated automatically per Simulator. A caller of the Framework does not need to know which transport is in use.

### `SimulatorKit.framework`

This is another macOS Framework that is used in iOS Simulator management. This Framework is not installed to the System, it is bundled within Xcode. Instead, this Framework is more used to implement functionality within `Simulator.app`.

For example, this Framework contains some of the `Indigo` client functionality for sending input events.

## Contributing
See the [contributing guide](../.github/CONTRIBUTING.md) for how to help out. There's plenty to work on in the issues!
