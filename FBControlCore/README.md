# FBControlCore

The base framework of the idb project: `FBSimulatorControl`, `FBDeviceControl` and `XCTestBootstrap` are all built on it. It defines the interfaces that make an iOS Simulator and an iOS Device interchangeable to callers, and provides the machinery those frameworks share.

Like the rest of the project, it is a mix of Objective-C and Swift, transitioning to pure Swift, and is usable from both languages.

## What it provides

- **Targets.** `FBiOSTarget` describes a single iOS Simulator or Device; `FBSimulator` and `FBDevice` implement it in their respective frameworks, so higher layers can treat a target uniformly regardless of its kind. `FBiOSTargetSet` is the counterpart for collections of targets.
- **Command protocols.** Functionality is defined as protocols, such as `ApplicationCommands`, implemented separately for Simulators and Devices. Protocols common to both are part of `FBiOSTarget`; target-specific ones are declared on the concrete classes. Older protocols are Objective-C and return an `FBFuture`; newer ones are Swift with `async` methods.
- **Configuration values.** Value types such as `FBApplicationLaunchConfiguration` gather the arguments to a call, providing defaults instead of long parameter lists.
- **Asynchrony.** The Objective-C core encapsulates asynchronous work in `FBFuture`; Swift code uses Swift Concurrency, with bridging between the two.
- **IO and processes.** Abstractions for reading and writing between sources and sinks (`FBFileReader`, `FBFileWriter`), and for spawning and supervising processes, backed by `libdispatch`.
- **Logging.** `FBControlCoreLogger` provides a common logging interface for all of the frameworks.

[The architecture documentation](https://www.fbidb.io/docs/idb/architecture) covers how these pieces fit together in `idb`.
