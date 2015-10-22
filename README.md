# FBSimulatorControl
A Mac OS X library for managing, booting and interacting with multiple iOS Simulators simultaneously.

[![Build Status](https://travis-ci.org/facebook/FBSimulatorControl.svg?branch=master)](https://travis-ci.org/facebook/FBSimulatorControl)

## Features
- Boots multiple iOS Simulators within the same host process or across processes.
- Does not have to be run from Xcode/`xcodebuild`. Simulators can be launched by a process that has not been spawned by Xcode.
- `NSNotification`s for the lifecycle of the Simulator and the user-launched processes.
- Boots Simulators across iOS 7, 8 & 9.
- Launching and switching between multiple Apps.
- Project has no external dependencies.
- Launch Applications and Agents with [Command Line Arguments](FBSimulatorControl/Configuration/FBProcessLaunchConfiguration.h#L24) and [Environment Variables](FBSimulatorControl/Configuration/FBProcessLaunchConfiguration.h#L29).
- APIs for [launching diagnostic utilities](FBSimulatorControl/Session/FBSimulatorSessionInteraction%2BDiagnostics.h) and attaching output to a Simulator session.
- BFFs with [`WebDriverAgent`](https://github.com/facebook/webdriveragent).

## About
The original use-case for `FBSimulatorControl` was to boot Simulators to run End-to-End tests with `WebDriverAgent`. As `FBSimulatorControl` is a Mac OS X framework, it can be linked to from inside any Mac OS Library, Application, or `xctest` target. There may be additional use-cases that you may find beyond UI Test Automation.

`FBSimulatorControl` works by linking with the private `DVTFoundation`, `CoreSimulator` and `DVTiPhoneSimulatorRemoteClient` frameworks that are present inside the Xcode bundle. Doing this allows  `FBSimulatorControl` to talk directly to the same APIs that Xcode and `simctl` do. This, combined with launching the Simulator binaries directly, means that multiple Simulators can be launched simultaneously. Test targets can be made that don't depend on any Application targets, or that launch multiple Application targets. This enables running against pre-built and archived Application binaries, rather than a binary that is built by a Test Target.

## Installation
The `FBSimulatorControl.xcodeproj` will build the `FBSimulatorControl.framework` and the `FBSimulatorControLTests.xctest` bundles as-is. The Project is checked-in to the repo.

Once you build the `FBSimulatorControl.framework`, it can be linked into your target like any other 3rd party framework. It does however need some additional linker flags (since it relies on Private Frameworks):

`FRAMEWORK_SEARCH_PATHS` should include `"$(DEVELOPER_LIBRARY_DIR)/Frameworks" "$(DEVELOPER_LIBRARY_DIR)/PrivateFrameworks" "$(DEVELOPER_DIR)/../SharedFrameworks" "$(SDKROOT)/System/Library/PrivateFrameworks" "$(OTHER_FRAMEWORKS_DIR)"`


`OTHER_LDFLAGS` should include `-rpath "$DEVELOPER_LIBRARY_DIR/Frameworks" -rpath "$DEVELOPER_LIBRARY_DIR/PrivateFrameworks" -rpath "$SDKROOT/System/Library/PrivateFrameworks" -rpath "$DEVELOPER_DIR/../SharedFrameworks" -rpath "$DEVELOPER_DIR/../Frameworks"`

## Usage
[The tests](FBSimulatorControlTests/Tests/FBSimulatorControlApplicationLaunchTests.m#L63) should provide you with some basic guidance for getting started. Run them to see multiple-simulator launching in action.

To launch Safari on an iPhone 5, you can use the following:

```objc
    FBSimulatorManagementOptions options =
      FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart |
      FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart |
      FBSimulatorManagementOptionsDeleteOnFree;
    
    FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
      configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
      namePrefix:nil
      bucket:0
      options:options];
    
    FBSimulatorControl *control = [[FBSimulatorControl alloc] initWithConfiguration:configuration];
    
    NSError *error = nil;
    FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
    
    FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
      configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
      arguments:@[]
      environment:@{}];
    
    // System Applications can be launched directly, User applications must be installed first with `installSimulator:`
    BOOL success = [[[session.interact
      bootSimulator]
      launchApplication:appLaunch]
      performInteractionWithError:&error];
```

For a high level overview:
- `FBSimulatorPool` is a responsible for booting and allocating simulators.
- `FBSimulator` is a wrapper around `SimDevice` that provides convenience methods and properties than `SimDevice` does not have.
- `FBManagedSimulator` is an extension of `FBSimulator` that has additional semantics around Simulator Management. Simulators are launched in a 'Managed' context to avoid interference with existing Simulators on the machine.
- `FBSimulatorSession` represents a transaction with a device. Sessions are started from `FBSimulatorPool` and terminated with the `terminateWithError:` method.
- `FBSimulatorSessionInteraction` contains a chainable interface for building interactions with the simulator. Calling `performWithError:` will synchronously perform the chained interactions.
- There are Configuration objects for bending many of these classes to your will.
- `FBSimulatorSession+Convenience` provides a simpler procedural API for launching an Application and an Agent.
- `FBSimulatorApplication` is a wrapper around Applications, you can create them for your own Apps or use `+[FBSimulatorApplication systemApplicationNamed:]` to launch System Apps.
- `FBApplicationLaunchConfiguration` describes the launch of an Application, it's arguments and environment.
- `FBSimulatorSessionState` provides a the current state and history of the known state of the Simulator, including the Unix Process IDs of the running Applications and Agents. You can further automate by using command line tools like [`sample(1)`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/sample.1.html), [`lldb(1)`](https://developer.apple.com/library/prerelease/mac/documentation/Darwin/Reference/ManPages/man1/lldb.1.html), [`heap(1)`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/heap.1.html) and [`instruments(1)`](https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/instruments.1.html).

## Multisim
`FBSimulatorControl` launches Xcode's Simulator Applications directly, allowing specific Simulators to be targeted by UDID. `Simulator.app` uses a default set of Simulators located at `~/Library/Developer/CoreSimulator/Devices`. By passing arguments to the `Simulator.app` binary, a different Device Set can be used, allowing multiple pools of Simulators to be booted, without interference.

This is only supported on Xcode 7.

## Contributing
See the [CONTRIBUTING](CONTRIBUTING) file for how to help out. There's plenty to work on the issues!

## License
[`FBSimulatorControl` is BSD-licensed](LICENSE). We also provide an additional [patent grant](PATENTS).
