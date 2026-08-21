# XCTestBootstrap

A macOS library for running XCTest bundles on iOS Simulators, iOS Devices and macOS.

`XCTestBootstrap` is primarily an implementation detail of `idb`, which uses it for all of its [test execution](https://www.fbidb.io/docs/idb/test-execution). Like the other frameworks in this repository it can be linked directly, and the same trade-off applies: the `idb` cli and its gRPC interface are the project's compatibility boundary; the framework's own APIs change more freely with the implementation.

## What it provides

- Listing the tests inside a built `.xctest` bundle, without running them.
- Running bundles in the three execution modes described in [the test execution documentation](https://www.fbidb.io/docs/idb/test-execution): logic tests without an app host, application tests inside an app host process, and UI tests coordinated through `testmanagerd`.
- The client side of the `DTX` protocol that Xcode's test infrastructure uses to communicate with `testmanagerd` on the target.
- Structured reporting of test results, so runs produce machine-readable output rather than only console text.
