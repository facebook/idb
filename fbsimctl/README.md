## fbsimctl

`fbsimctl` is a command line interface to the `FBSimulatorControl` Framework. It is a Command Line Executable Target. It is a wrapper around `FBSimulatorControlKit` which is where the important functionality of the Command-Line Application is implemented. It is a pure Objective-C target.

## FBSimulatorControlKit

`FBSimulatorControlKit` is a Framework that forms the core functionality in `fbsimctl`. It is a mixed Objective-C/Swift Framework and is linkable from both a test and executable target. As `fbsimctl` is a pure Objective-C Framework it does not need to link the Swift shims to Mac OS X Frameworks.

