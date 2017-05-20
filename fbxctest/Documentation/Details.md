# Types of Test Bundles

iOS Simulators support a range of different Test Bundles, each of which has different runtime requirements.

### `.xctest` bundles

An `xctest` bundle is fundamentally a Dynamically Linked Framework. `xctest` bundles are loaded at runtime by the process that they are being injected into, just like a plugin or shim. The dynamic library within the Framework will link with `XCTest.framework` and can also link with other System-Level Frameworks, or images that are present inside the process that it is being injected into.

### Logic Tests

A Test Bundle that can run in the context of any process, typically used for Unit Tests. These kinds of `xctest` bundles do not typically require a specific host Application as all code-under-test is linked as a dependency of the Test Bundle itself. Like all `xctest` bundles, they can dynamically link the code-under-test at runtime, or statically links the tested code inside the Test Bundle's dynamic library.

Logic tests are typically injected into a small host process like the `xctest` commandline. macOS has a `xctest` commandline at `/usr/bin/xctest/`, the iOS Simulator `xctest` executable is located at `$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest`. The `xctest` commandline will load the `xctest` bundle provided as an argument and run tests according to the arguments, or from an `XCTestConfigurationFilePath` provided as an environment variable passed to the process.

### Application Tests

Applications are similar to logic tests, but they run inside an iOS App Host Process. This is typically used for Unit & Integration tests that depend on an Application's code, or running inside the context of an Application.

These tests can manipulate the UI within an Application, depend certain behaviours of `UIKit`, or interact with the Application Delegate.

### UI Tests

In Xcode 7, Apple deprecated `UIAutomation` and replaced it with UI Testing support inside the `XCTest` framework itself. This means that UI Tests have a similar execution model to Application Tests, by injecting into an Application Process.

As part of the security model of running these tests, the Test Bundle cannot manipulate the User Interface un-aided. The bundle running inside the Application process co-ordinates with Xcode via a daemon process called `testmanagerd`. This mediated connection between the injected Application process and IDE Host also allows for [test results to be delivered across a delegate protocol to the IDE Host](https://github.com/facebook/FBSimulatorControl/blob/master/PrivateHeaders/XCTest/XCTestManager_IDEInterface-Protocol.h).

## Rationale

`fbxctest` aims to solve a number of problems.

## Structured Output

`xcodebuild` and the `xctest` commandline both output to a human-readable format over `stdout`. This provides great readability, but makes it difficult to integrate with many other systems that want to parse the output and use it in some other way. There are a [multiple](https://github.com/facebook/xctool#reporters) [projects](https://github.com/supermarin/xcpretty) that

There are a number of reporting systems out there that have been adopted by a host.

## A Testrunner without a full build chain

As `xcodebuild` is a commandline interface to `Xcode` it inherits a lot of Xcode's functionality. This means that `xcodebuild` can be used to build Applications, Frameworks, Tests as well as run them. There are other [alternative build-systems for iOS Development](https://buckbuild.com). For these tools, an entire commandline to a modern IDE is excessive, when a single executable that is specialized for running tests is sufficient.

## A better `test-without-building`.

In Xcode 8, Apple added the `test-without-building` action to `xcodebuild`'s commandline. This allows `xcodebuild` to be used with a pre-built test bundle.

This is great news for people who want to 'build once, run everywhere'. However there are a number of problems with this:

- Concurrency. In the case of running UI Tests, `xcodebuild` cannot run [tests at the same time on multiple iOS Simulators](https://github.com/facebook/FBSimulatorControl). This is problematic for those who wish to get more test throughput out of their test hosts. For this reason, the [`XCTestBootstrap` Framework was created](https://github.com/facebook/FBSimulatorControl/blob/master/XCTestBootstrap/README.md), upon which `fbxctest` depends.
- A Simple UI. The supported interface of specifying a format for `xcodebuild` is to generate a `plist` for the `xcodebuild` CLI and pass it as an argument with the `-xctestrun` parameter. `fbxctest` is
- Streaming Results. `xcodebuild` delivers it's results back to the caller of the process in a structured way by using the `-resultBundlePath`. The test results are reported to a bundle, which contains information about the status of all the tests that have been run, which requires re-parsing. This means that results must be extracted from this bundle at the end of a test run and cannot be read incrementally. As mentioned in [Structured Output], there are already a number of de-facto standards that integrate well with automation which can also work with streaming output.

## Optimisations for Logic Tests

When Logic Tests are launched via the Simulator's `xctest` commandline, the `xctest` process doesn't have any dependencies on helper processes like `testmanagerd` for reporting results to `stdout`. As the the iPhone Simulator Platform runs on macOS without any emulation, the `xctest` commandline can be launched directly by setting the appropriate `DYLD` environment variables for ensuring that the executable links with the appropriate iPhone Simulator System Frameworks, instead of the root-level macOS Frameworks.

Unlike [Xcode's Framework dependencies](https://gist.github.com/lawrencelomax/7c36f447c819502f12f67173132607e6), the `xctest` commandline is not codesigned. This means that a shim can be injected into the `xctest` process without having to defeat codesigning. By using a shim, the [internal reporting calls of `XCTest.framework` linked by the `xctest` commandline can be swizzled](https://github.com/facebook/xctool/blob/master/otest-shim/otest-shim/otest-shim.m), and structured data can instead be written to `stdout`.

With these two principles in mind, this is how [`xctool` runs `xctest` bundles without a booted Simulator](https://github.com/facebook/xctool/blob/master/xctool/xctool/OCUnitIOSLogicTestRunner.m) and gets structured output instead of the default output of `xctest`. `fbxctest` will use a similar strategy to run logic tests and get the same output.

This is not currently implemented.
