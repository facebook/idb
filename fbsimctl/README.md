## fbsimctl

`fbsimctl` is a command line interface to the `FBSimulatorControl` Framework.

## FBSimulatorControlKit

`FBSimulatorControlKit` is a Framework that forms the core functionality in `fbsimctl`. It is created as an additional target so that the components of `fbsimctl` can be linked from the `FBSimulatorControlKitTests` target.

Unfortunately, there is an issue with Swift and it's usage with Frameworks that need to be overcome in order for `FBSimulatorControlKit` to be a dependency of `fbsimctl`. The [Swift Standard Libraries](https://developer.apple.com/library/ios/qa/qa1881/_index.html) end up being copied as `dylib`s for `FBSimulatorControlKit` and end up being embedded in the `fbsimctl` binary. This means that these symbols are exported and loaded twice.

Currently, instead of linking the `FBSimulatorControlKit` framework from `fbsimctl`, the files are included in both targets so that:
1) `fbsimctl` can use them without duplicate symbols.
2) `FBSimulatorControlKit` is a testable framework with a test target.
