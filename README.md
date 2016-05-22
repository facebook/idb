# FBSimulatorControl
A Mac OS X library for managing, booting and interacting with multiple iOS Simulators simultaneously.

[![Build Status](https://travis-ci.org/facebook/FBSimulatorControl.svg?branch=master)](https://travis-ci.org/facebook/FBSimulatorControl)

## Features
- Enables 'Multisim' for iOS: Booting of multiple Simulators on the same host OS.
- Runs independently of Xcode and `xcodebuild`. Uses the toolchain defined by `xcode-select`. 
- Boots iPhone & iPad Simulators for iOS 7, 8 & 9.
- Boots watchOS Simulators since watchOS 2.0.
- Boots tvOS Simulators since tvOS 9.0.
- Launches both 'Agent' and 'Application' processes, with Arguments and Environment.
- Can boot Simulators via Xcode's `Simulator.app` or by launching 'Directly' in `CoreSimulator`.
- 'Direct Launch' supports video recording, screenshot fetching & interfacing with the `SimulatorBridge`.
- 'Diagnostic' API for fetching System, App & Crash logs as well as Screenshots & Video.
- An 'Event Bus' that exposes the details of a Simulator's lifecycle including Applications, Agents & the Simulator itself.
- Persistent and Queryable history of all events in Simulator's lifecycle.
- `NSNotification`s interface for the 'Event Bus'.
- Stateless by Default: Knowledge the current state of Simulators can be re-built when `FBSimulatorControl` is launched.
- BFFs with [`WebDriverAgent`](https://github.com/facebook/webdriveragent).
- No external dependencies.

## About
The original use-case for `FBSimulatorControl` was to boot Simulators to run End-to-End tests with `WebDriverAgent`. As `FBSimulatorControl` is a Mac OS X framework, it can be linked to from inside any Mac OS Library, Application, or `xctest` target. There may be additional use-cases that you may find beyond UI Test Automation.

`FBSimulatorControl` works by linking with the private `DVTFoundation`, `CoreSimulator` and `DVTiPhoneSimulatorRemoteClient` frameworks that are present inside the Xcode bundle. Doing this allows  `FBSimulatorControl` to talk directly to the same APIs that Xcode and `simctl` do. This, combined with launching the Simulator binaries directly, means that multiple Simulators can be launched simultaneously. Test targets can be made that don't depend on any Application targets, or that launch multiple Application targets. This enables running against pre-built and archived Application binaries, rather than a binary that is built by a Test Target.

As `FBSimulatorControl` nears a stable version, the API may change but can be considered mostly stable.

## Installation
The `FBSimulatorControl.xcodeproj` will build the `FBSimulatorControl.framework` and the `FBSimulatorControlTests.xctest` bundles without any additional dependencies. The Project File is checked into the repo and the Framework can be build from this project.

Once you build the `FBSimulatorControl.framework`, it can be linked like any other 3rd-party Framework for your project:
- Add `FBSimulatorControl.framework` to the [Target's 'Link Binary With Libraries' build phase](Help/link_binary_with_libraries.png).
- Ensure that `FBSimulatorControl` is copied into the Target's bundle (if your Target is an Application or Framework) or a path relative to the Executable if your project does not have a bundle.

## Usage
In order to support different Xcode versions and system environments, `FBSimulatorControl` weakly links against Xcode's Private Frameworks and load these Frameworks when they are needed. `FBSimulatorControl` will link against the version of Xcode that you have set with [`xcode-select`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcode-select.1.html). The Xcode version can be overridden by setting the `DEVELOPER_DIR` environment variable in the process that links with `FBSimulatorControl`.

Since the Frameworks upon which `FBSimulatorControl` depends are loaded laziliy, they must be loaded before using the Framework. Any of the `FBSimulatorControl` classes that have this runtime dependency will load these Private Frameworks when they are used for the first time.

[The tests](FBSimulatorControlTests/Tests) should provide you with some basic guidance for using the API. `FBSimulatorControl` has an umbrella that can be imported to give access to the entire API.

For a high level overview:
- `FBSimulatorControl` is the Principal Class. It is the first object that you should create with `+[FBSimulatorControl withConfiguration:error:]`. It creates a `FBSimulatorPool` upon creation.
- `FBSimulatorSet` wraps `SimDeviceSet` and provides a resiliant CRUD API for Deleting, Creating and Erasing Simulators.
- `FBSimulatorPool` builds on `FBSimulatorSet` by providing an 'Allocation' API that allows Simulators to be reserved and re-used within the Framework.
- `FBSimulator` is a reference type that represents an individual Simulator. It has a number of convenience methods for accessing information about a Simulator.
- `FBSimulatorInteraction` and it's categories forms the API of possible ways of interacting with a Simulator. These range from booting Simulators, installing & running Applications, uploading photos & videos and more.
- `FBSimulatorHistory` is a record of all the events that happen to a Simulator. It can be queried in a variety of ways and serialized to file.
- `FBSimulatorDiagnositcs` is a facade around available diagnostics for a Simulator. It fetches static logs such as the System Log on-demand and receives new logs from components such as `FBFramebufferVideo`.
- Configuration objects: `FBApplicationLaunchConfiguration`, `FBAgentLaunchConfiguration`, `FBSimulatorApplication`, `FBSimulatorControlConfiguration`, `FBSimulatorConfiguration` & `FBSimulatorLaunchConfiguration`.

To launch Safari on an iPhone 5, you can use the following:

```objc

    // Create a suitable configuration for FBSimulatorControl.
    // This Configuration will ensure that no other Simulators are running.
    FBSimulatorManagementOptions managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart;    
    FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:nil
      options:managementOptions];
    
    // The principal class, must be retained as long as the Framework is used.
    // If there is something wrong with the environment and error will be returned.
    NSError *error = nil;
    FBSimulatorControl *control = [FBSimulatorControl withConfiguration:controlConfiguration error:&error];
    
    // Create the Configuration for the Allocation & Creation of a Simulator.
    // When a Simulator is Allocated, a Simulator matching the given configuration is reused if one is available
    // Otherwise a Simulator with the provided configuration will be created.
    // The Simulator returned as a result will be shutdown and erased.
    FBSimulatorConfiguration *simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
    FBSimulatorAllocationOptions allocationOptions = FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsReuse | FBSimulatorAllocationOptionsEraseOnAllocate;
    
    // Obtain a Simulator from the Principal Class. If anything goes wrong, nil will be returned along with a descriptive error.
    FBSimulator *simulator = [control.pool allocateSimulatorWithConfiguration:simulatorConfiguration options:allocationOptions error:&error];

    
    // Build a Launch Configuration.
    FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
      configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari" error:&error]
      arguments:@[]
      environment:@{}
      options:0];
    
    // System Applications can be launched directly since they are already 'installed' in the Simulator.
    // Applications provided by the user must be installed after Booting with `installApplication:`.
    BOOL success = [[[simulator.interact
      bootSimulator]
      launchApplication:appLaunch]
      perform:&error];
```


`FBSimulatorControl` currently has two ways of launching Simulators that have tradeoffs for different use cases. Since Xcode 7.2, both these methods can be used:

## Multisim
The `CoreSimulator` Framework that is used by the `Simulator.app` as well as Playgrounds & Interface Builder has long had the concept of custom 'Device Sets' which contain created Simulators. Multiple Device Sets can be used on the same host and are an effective way of ensuring that multiple processes using `CoreSimulator` don't collide into each other. 'Device Sets' are also beneficial for an automation use-case, as using a different set other than the 'Default' will ensure that these Simulators aren't polluted.

`CoreSimulator` itself is also capable of running multiple Simulators on the same host concurrently. You can see this for yourself by using the `simctl` commandline. Booting Simulators this way can be of somewhat limited utility without the output of the screen. `FBSimulatorControl` solves this problem in two different ways:

## Launching via `Simulator.app`
`Simulator.app` is the Mac OS X Application bundle with Xcode that you are probably familiar with for viewing and interacting with a Simulator. This Mac Application is the part of the Xcode Toolchain that you will be used to.

`FBSimulatorControl` can launch the Application Excutable directly, thereby allowing specific Simulators to be booted by UDID and Device Set. This can be done by overriding the `Simulator.app`s `NSUserDefaults` by [passing them as Arguments to the Application Process](https://www.bignerdranch.com/blog/by-your-command). Once the Simulator has booted, it can be interacted with via `CoreSimulator` with commands such as installing Apps and launch executables.

However, this mode of operation does limit the amount that `FBSimulatorControl` can manipulate the Simulator, once the `Simulator.app` process has been launched. In particular it's not [possible to execute custom code inside the Simulator Application process](https://gist.github.com/lawrencelomax/27bdc4e8a433a601008f), which means that it's not possible to get video frames that the booted simulator passes back to the `Simulator.app` process.

## Direct Launch
`FBSimulatorControl` also supports 'Direct Launching'. This means that the Simulator is booted from the `FBSimulatorControl` Framework. This gives increasing control over the operation of the Simulator, including fetching frames from the Framebuffer. This means that pixel-perfect videos and screenshots can be constructed from the Framebuffer. In addition, `FBSimulatorControl` can [communicate to the `SimulatorBridge`](https://github.com/facebook/FBSimulatorControl/blob/master/FBSimulatorControl/Management/FBSimulatorBridge.h) process running on the Simulator over XPC.

Direct Launching does not currently support manipulation of the UI within the Simulator, so is much better suited to a use-case where the [UI is manipulated by other means](https://github.com/facebook/webdriveragent).

## `fbsimctl`
[`fbsimctl` is a Command Line Interface](https://github.com/facebook/FBSimulatorControl/blob/master/fbsimctl/README.md) for `FBSimulatorControl` API calls, so `FBSimulatorControl` functionality can be used without the need to integrate with the Framework. It is currently under development. As `fbsimctl` is under active development, the User Interface will be prone to change.

## Contributing
See the [CONTRIBUTING](CONTRIBUTING) file for how to help out. There's plenty to work on the issues!

## Example Projects

* [fbsimctl](https://github.com/facebook/FBSimulatorControl/blob/master/fbsimctl/README.md): Command line interface
* [SimulatorController](https://github.com/davidlawson/SimulatorController): GUI interface written in Swift
* [FBSimulatorClient](https://github.com/tapthaker/FBSimulatorClient): Simulator interface using REST requests

## License
[`FBSimulatorControl` is BSD-licensed](LICENSE). We also provide an additional [patent grant](PATENTS).
