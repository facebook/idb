# FBSimulatorControl
A Mac OS X library for managing, booting and interacting with multiple iOS Simulators simultaneously.

[![Build Status](https://travis-ci.org/facebook/FBSimulatorControl.svg?branch=master)](https://travis-ci.org/facebook/FBSimulatorControl)

## Features
- Boots multiple iOS Simulators within the same host process or across processes.
- Does not have to be run from Xcode/`xcodebuild`. Simulators can be launched by a process that has not been spawned by Xcode.
- `NSNotification`s for the lifecycle of the Simulator and user-launched processes.
- Boots Simulators across iOS 7, 8 & 9.
- Launching and switching between multiple Apps.
- Convenient fetching of System, App & Crash logs.
- Persistent and Queryable history of all Simulator events.
- Knowledge about the state of all Simulators can be re-built when `FBSimulatorControl` is launched.
- No external dependencies.
- Launch Applications and Agents with [Command Line Arguments](FBSimulatorControl/Configuration/FBProcessLaunchConfiguration.h#L24) and [Environment Variables](FBSimulatorControl/Configuration/FBProcessLaunchConfiguration.h#L29).
- APIs for [launching diagnostic utilities](FBSimulatorControl/Session/FBSimulatorSessionInteraction%2BDiagnostics.h) and attaching output to a Simulator session.
- BFFs with [`WebDriverAgent`](https://github.com/facebook/webdriveragent).

## About
The original use-case for `FBSimulatorControl` was to boot Simulators to run End-to-End tests with `WebDriverAgent`. As `FBSimulatorControl` is a Mac OS X framework, it can be linked to from inside any Mac OS Library, Application, or `xctest` target. There may be additional use-cases that you may find beyond UI Test Automation.

`FBSimulatorControl` works by linking with the private `DVTFoundation`, `CoreSimulator` and `DVTiPhoneSimulatorRemoteClient` frameworks that are present inside the Xcode bundle. Doing this allows  `FBSimulatorControl` to talk directly to the same APIs that Xcode and `simctl` do. This, combined with launching the Simulator binaries directly, means that multiple Simulators can be launched simultaneously. Test targets can be made that don't depend on any Application targets, or that launch multiple Application targets. This enables running against pre-built and archived Application binaries, rather than a binary that is built by a Test Target.

## Installation
The `FBSimulatorControl.xcodeproj` will build the `FBSimulatorControl.framework` and the `FBSimulatorControlTests.xctest` bundles without any additional dependencies. The Project File is checked into the repo and the Framework can be build from this project.

Once you build the `FBSimulatorControl.framework`, it can be linked like any other 3rd-party Framework for your project:
- Add `FBSimulatorControl.framework` to the [Target's 'Link Binary With Libraries' build phase](Help/link_binary_with_libraries.png).
- Ensure that `FBSimulatorControl` is copied into the Target's bundle (if your Target is an Application or Framework) or a path relative to the Executable if your project does not have a bundle.

In order to support different environments, `FBSimulatorControl` weakly links against Xcode's Private Frameworks and then loads them on startup. `FBSimulatorControl` will link against the version of Xcode that you have set with [`xcode-select`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcode-select.1.html). The Xcode version can be overridden by setting the `DEVELOPER_DIR` environment variable in the process that links with `FBSimulatorControl`.

## Usage
[The tests](FBSimulatorControlTests/Tests) should provide you with some basic guidance for using the API. `FBSimulatorControl` has an umbrella that can be imported to give access to the entire API.

For a high level overview:
- `FBSimulatorControl` is the principal class. It is the first object that you should create with `+[FBSimulatorControl withConfiguration:error:]`. It creates a `FBSimulatorPool` upon creation.
- `FBSimulatorPool` is responsible for managing the allocation and freeing of Simulators. It will also ensure that the running environment is in a clean state before attempting to manipulate Simulators.
- `FBSimulator` is a reference type that represents an individual Simulator. It has a number of convenience methods for accessing information about a Simulator.
- `FBSimulatorInteraction` and it's categories forms the API of possible interactions with a Simulator. These range from booting Simulators, installing & running Applications, uploading photos & videos and more.
- `FBSimulatorHistory` is a record of all the events that happen to a Simulator. It can be queried in a variety of ways and serialized to file.
- `FBSimulatorLogs` is a facade around available logs for a Simulator.
- `FBSimulatorLaunchInfo` describes the launch environment of a Simulator and it's subprocesses.
- Configuration objects: `FBApplicationLaunchConfiguration`, `FBAgentLaunchConfiguration`, `FBSimulatorApplication`, `FBSimulatorControlConfiguration` & `FBSimulatorConfiguration`.

To launch Safari on an iPhone 5, you can use the following:

```objc

    // Create a suitable configuration for FBSimulatorControl.
    // This Configuration will ensure that no other Simulators are running.
    FBSimulatorManagementOptions managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart;    
    FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
      configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
      deviceSetPath:nil
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
    
    // Allocate the Simulator. If anything goes wrong, nil will be returned along with a descriptive error.
    FBSimulator *simulator = [control.simulatorPool allocateSimulatorWithConfiguration:simulatorConfiguration simulatorConfiguration options:options error];
    
    // Build a Launch Configuration.
    FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
      configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
      arguments:@[]
      environment:@{}];
    
    // System Applications can be launched directly since they are already 'installed' in the Simulator.
    // Applications provided by the user must be installed after Booting with `installApplication:`.
    BOOL success = [[[simulator.interact
      bootSimulator]
      launchApplication:appLaunch]
      performInteractionWithError:&error];
```


## Multisim
`FBSimulatorControl` launches Xcode's Simulator Applications directly, allowing specific Simulators to be targeted by UDID. `Simulator.app` uses a default set of Simulators located at `~/Library/Developer/CoreSimulator/Devices`. By passing arguments to the `Simulator.app` binary, a different Device Set can be used, allowing multiple pools of Simulators to be booted, without interference.

This is only supported on Xcode 7.

## Contributing
See the [CONTRIBUTING](CONTRIBUTING) file for how to help out. There's plenty to work on the issues!

## License
[`FBSimulatorControl` is BSD-licensed](LICENSE). We also provide an additional [patent grant](PATENTS).
