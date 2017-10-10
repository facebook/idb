# Rationale & Architecture

The `FBSimulatorControl` Framework exposes a lot of functionality over it's API surface. The Framework can be dropped in to any macOS App, CLI or  Test Projects, an the API can be used directly. This isn't super-convenient for many Users who just want access to `FBSimulatorControl` in the fastest and simplest way possible.

`fbsimctl` is Command Line Application written in Swift that links with the `FBSimulatorControl` Framework. Swift is well-suited to writing Command-Line Applications and the interoperability with Objective-C means that `fbsimctl` can have a small footprint, instead choosing to use as much of the `FBSimulatorControl` Framework as possible. Where `FBSimulatorControl` has a very configurable API, `fbsimctl` takes more of a 'batteries-included' approach to interacting with Simulators. This means that `fbsimctl` will choose reasonable defaults where appropriate.

As Xcode can't test Executables directly a separate Framework target `FBSimulatorControlKit` is used to contain the core functionality of `fbsimctl`. These components are tested in the`FBSimulatorControlKitTests` target. The `fbsimctl` executable itself is very small, it just calls a bootstrap command inside `FBSimulatorControlKit` with the arguments and environment variables passed to the process on launch.

A video from [SeleniumConf London 2016 is available](https://www.youtube.com/watch?v=lTxW4rbu6Bk), which gives a high-level overview of the problems that `fbsimctl` was created to solve.
