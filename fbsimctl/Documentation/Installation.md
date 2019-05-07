# Installation

When building `fbsimctl`, you must be using Xcode 8 or greater. Building with Xcode 7 is not supported.

## [Homebrew](http://brew.sh)

 The quickest way to get going with `fbsimctl` is to use the Homebrew Formula:

```bash
# Get the Facebook Tap.
brew tap facebook/fb
# Install fbsimctl from master
brew install fbsimctl --HEAD
```

## Custom Installation

The Formula uses the [build script at the root of the `FBSimulatorControl` repo](https://github.com/facebook/FBSimulatorControl/blob/master/build.sh). You can use this to create a `fbsimctl` build, with all associated Frameworks into a directory.

```
# Carthage is required
$ brew install carthage
# Build fbsimctl and place it in the 'output' directory
$ ./build.sh fbsimctl build output
# Lists all Simulators & Devices
$ ./output/bin/fbsimctl list
```

The `output` directory can be relocated on disk wherever you wish, the directory contains all the necessary dependencies in the directory. You can zip the package up and move it anywhere, or add the directory to your shell's `PATH`.
