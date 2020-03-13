---
id: test-execution
title: Test Execution
---

Test execution is a well-supported feature of idb. Supporting `xctest run` as a primitive means that idb can be used in automated scenarios such as continuous integration or IDEs.

There are three areas that idb aims to solve on top of Xcode and `xcodebuild`:

1. Structured Output: idb will output machine readable output when using the `--json` flag. This is often required for CI systems. `xcodebuild` now supports the `-resultBundlePath` flag, which outputs a plist upon completion, but idb also exposes streaming output and can support custom reporters.
2. Build Once, Run Many, Run Repeated: `xcodebuild` currently supports "Run Many" with the `test-without-building` command. However, this imposes more of a burden on the user than is necessary. In many cases idb supports building a singular `.xctest` bundle and `xctest install`ing this. This makes it easier to distribute test bundles against many runtimes and also run the same test bundle with a different runtime environment. For example, idb can run the same bundle with different environment variables, without modifying the build output. This makes it ideal for parameterizing the same test bundle with different data inputs. Or running the same test bundle in an Application or Logic Test context.
3. Listing of Tests: Given an installed test bundle idb also supports listing of tests within a bundle. This means that the user can peek at what tests cases are in a bundle without parsing sources using `xctest list`
4. Faster test execution environments: "Logic Test" execution is an optimization that idb can use in a Simulator environment. This means that a test can execute much faster by not being injected into a full Application context. If test bundles are fast to execute, idb doesn't impose a cost of launching an Application.

## Installation of Test Bundles

Since iOS Runtimes may be remote from the machine that is executing idb commands, idb needs to support the concept of `installation`. This is essentially copying across the test bundle artifacts alongside the runtime using `xctest install`. 

By doing so, the idb companion backend then has the test bundle binary to execute against when using `xctest run`. These bundles are also persisted, which makes caching of test bundles more feasible.

The following shows the installation of a test bundle, listing the available bundles, then the test cases within a installed bundle:

```
$ idb xctest install Fixtures/Binaries/iOSUnitTestFixture.xctest
Installed: com.facebook.iOSUnitTestFixture
$ idb xctest list
com.facebook.iOSUnitTestFixture | iOSUnitTestFixture | x86_64, i386
$ idb xctest list-bundle com.facebook.iOSUnitTestFixture
iOSUnitTestFixtureTests/testHostProcessIsMobileSafari
iOSUnitTestFixtureTests/testHostProcessIsXctest
iOSUnitTestFixtureTests/testIsRunningInIOSApp
iOSUnitTestFixtureTests/testIsRunningInMacOSXApp
iOSUnitTestFixtureTests/testIsRunningOnIOS
iOSUnitTestFixtureTests/testIsRunningOnMacOSX
iOSUnitTestFixtureTests/testPossibleCrashingOfHostProcess
iOSUnitTestFixtureTests/testPossibleStallingOfHostProcess
iOSUnitTestFixtureTests/testWillAlwaysFail
iOSUnitTestFixtureTests/testWillAlwaysPass
```

This makes the process of `xctest` management a lot more similar to app management. Using a given test bundle, it's then trivial to execute tests against it

```
$ idb xctest run logic --json com.facebook.iOSUnitTestFixture                                                                                                                                                                                                                         
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testHostProcessIsMobileSafari", "logs": [], "duration": 0.22353005409240723, "passed": false, "crashed": false, "failureInfo": {"message": "(([NSProcessInfo.processInfo.processName isEqualToString:@\"MobileSafari\"]) is true) failed", "file": "/repo_root/iOSUnitTestFixture/iOSUnitTestFixtureTests.m", "line": 50}, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testHostProcessIsXctest", "logs": [], "duration": 0.0002950429916381837, "passed": true, "crashed": false, "failureInfo": null, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testIsRunningInIOSApp", "logs": [], "duration": 0.0003999471664428711, "passed": false, "crashed": false, "failureInfo": {"message": "(([NSClassFromString(@\"UIApplication\") performSelector:@selector(sharedApplication)]) != nil) failed", "file": "/repo_root/iOSUnitTestFixture/iOSUnitTestFixtureTests.m", "line": 30}, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testIsRunningInMacOSXApp", "logs": [], "duration": 0.00030100345611572255, "passed": false, "crashed": false, "failureInfo": {"message": "(([NSClassFromString(@\"NSApplication\") performSelector:@selector(sharedApplication)]) != nil) failed", "file": "/repo_root/iOSUnitTestFixture/iOSUnitTestFixtureTests.m", "line": 40}, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testIsRunningOnIOS", "logs": [], "duration": 0.0002809762954711914, "passed": true, "crashed": false, "failureInfo": null, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testIsRunningOnMacOSX", "logs": [], "duration": 0.0003479719161987306, "passed": false, "crashed": false, "failureInfo": {"message": "((NSClassFromString(@\"NSView\")) != nil) failed", "file": "/repo_root/iOSUnitTestFixture/iOSUnitTestFixtureTests.m", "line": 35}, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testPossibleCrashingOfHostProcess", "logs": [], "duration": 0.0003750324249267579, "passed": true, "crashed": false, "failureInfo": null, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testPossibleStallingOfHostProcess", "logs": [], "duration": 0.00037300586700439453, "passed": true, "crashed": false, "failureInfo": null, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testWillAlwaysFail", "logs": [], "duration": 0.0002980232238769531, "passed": false, "crashed": false, "failureInfo": {"message": "failed - This always fails", "file": "/repo_root/iOSUnitTestFixture/iOSUnitTestFixtureTests.m", "line": 76}, "activityLogs": []}
{"bundleName": "iOSUnitTestFixtureTests", "className": "iOSUnitTestFixtureTests", "methodName": "testWillAlwaysPass", "logs": [], "duration": 0.00024402141571044914, "passed": true, "crashed": false, "failureInfo": null, "activityLogs": []}
```

## What is a Test Bundle?

An `xctest` bundle is fundamentally a Dynamically Linked Framework that contains executable test code.

`xctest` bundles are loaded at runtime by the process that they are being injected into, just like a plugin or shim. The dynamic library within the `.xctest` bundle links with [`XCTest.framework`](https://developer.apple.com/documentation/xctest) and can also link with other System-Level Frameworks, or code that is statically linked inside the test bundle.

Since these bundles aren't substantially different to any other Framework or dynamic library, they can be relocated onto another machine, or amongst many iOS runtimes on the current machine.

## iOS Simulators

Simulators are a common place to execute test bundles, especially when testing unit or integration level functionality that may not have dependencies on running a physical device.

The performance differences between a Simulator and Device are also less relevant if you only care about correctness. Simulators are often easier to manage within a CI environment.

There are a number of test execution environments that idb supports:

### Logic Tests: `idb xctest run logic`

A Test Bundle that can run in the context of any process, typically used for Unit Tests. These kinds of `xctest` bundles do not typically require a specific host Application as all code-under-test.

Like all `xctest` bundles, they can dynamically link the code-under-test at runtime, or statically links the tested code inside the Test Bundle's dynamic library.

Logic tests are typically injected into a small host process like the `xctest` commandline. macOS has a `xctest` commandline at `/usr/bin/xctest/`, the iOS Simulator `xctest` executable is located at `$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest`.

The `xctest` commandline will load the `xctest` bundle provided as an argument and run tests according to the arguments, or from an `XCTestConfigurationFilePath` provided as an environment variable passed to the process.

idb then injects a shim into the `xctest` process and hooks calls to `XCTest.framework` methods. This is then used to report results back to idb. This communication happens via a FIFO, passed into the spawned `xctest` process.

This is not a mode of execution that is supported by Xcode & `xcodebuild`. However, if you're wanting to optimize the performance of your test executions, for instance to get faster signal on code changes, then this is a worthy optimization. The main reason for not using "Logic Tests" is if the Test code or the code-under-test requires an application context, for instance if it's using `UIApplication`. As such, Logic Tests are often well suited to business or domain logic that doesn't depend on much more than Foundation, or your own libraries.

### Application Tests: `idb xctest run app`

Application Tests are similar to Logic Tests, but they run inside an iOS App Host Process. This is typically used for Unit & Integration tests that depend on an Application's code, or running inside the context of an Application.

These tests can manipulate the UI within an Application, depend certain behaviours of `UIKit`, or interact with the Application Delegate. They require a little more work to bootstrap, because of the arbitration between idb and the host process.

idb uses `XCTestBootstrap` which understands how to perform this arbitration and translate delegate callbacks into machine-readable output.

### UI Tests: `idb xctest run ui`

In Xcode 7, Apple deprecated `UIAutomation` and replaced it with UI Testing support inside the `XCTest` framework itself. This means that UI Tests have a similar execution model to Application Tests, by injecting into an Application Process.

As part of the security model of running these tests, the Test Bundle cannot manipulate the User Interface un-aided. The bundle running inside the application process coordinates with Xcode via a daemon process called `testmanagerd`.

This mediated connection between the injected application process and IDE Host also allows for [test results to be delivered across a delegate protocol to the IDE Host](https://github.com/facebook/FBSimulatorControl/blob/master/PrivateHeaders/XCTest/XCTestManager_IDEInterface-Protocol.h).

## idb and Shims

In order for idb to extract structured output from a test process, it uses a "shim": a dynamically linked library that can interpose some of the functionality of `XCTest.framework`.

The default installation instructions for idb will create shims for you. If you're re-locating the `idb_companion` you should take a [look at this class](https://github.com/facebook/idb/blob/master/XCTestBootstrap/Configuration/FBXCTestShimConfiguration.m), which describes how idb finds these binaries.

## What about `fbxctest`?

`fbxctest` was built as a drop-in replacement for `xctool` before it. idb doesn't have the same command-line interface for test execution, so you will need to invoke idb differently to use it.

`fbxctest` will remain around for the foreseeable future, as both idb and `fbxctest` depend on the same underlying `XCTestBootstrap` framework. `fbxctest` may be deprecated in the future.
