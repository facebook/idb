# idb

![idb logo](docs/assets/idb_logo_color.jpg)

The “iOS Development Bridge” or `idb`, is a command line interface for automating iOS Simulators and Devices for development. It has three main goals:

* *Remote Automation.* `idb` has a “companion” that runs on macOS and a python client and cli that runs anywhere. This enables scenarios such as a “Device Lab” within a Data Center or fanning out commands to large numbers of iOS Simulators.
* *Simple Primitives.* `idb` exposes granular APIs that enable building more sophisticated workflows on top. This means you can use `idb` from an IDE or build an automated testing scenario that is more than just running a set of tests. All of these primitives are consistent across OS Versions and between Simulators and Devices. The cli is intended to also be easy to use for humans as well as automation, as such it provides terse and self-documenting commands.
* *Exposing missing functionality.* Xcode has a number of features that aren't available outside it's own UI. `idb` exposes many of these features so that they can be used within other GUI-less automation.

`idb` is largely built from the `FBSimulatorControl` and `FBDeviceControl` Frameworks, contained within this repository. These Frameworks can be used independently of `idb`, but `idb` is likely to provide the simplest install and the most sensible defaults for most users.

We will be giving a talk about `idb` at F8 on [Wednesday 1st May 2019](https://www.f8.com/schedule). You can watch the [live-stream of the event here](https://www.f8.com/watch), a recording will be released shortly afterwards.

## Quick Start
**Under Construction**
please bear with us. the quick start steps might not be working for you yet.

`idb` is made up of 2 parts, each of which needs to be installed separately.

### `idb` companion

Each target (simulator/device) will have a companion process attached allowing `idb` to communicate remotely.

The `idb` companion can be installed via brew or built from [source](https://github.com/facebook/idb)
```
brew tap facebook/fb
brew install idb-companion
```
Note: Instructions on how to install brew can be found [here](https://brew.sh)

### `idb` client

A cli tool and python client is provided to interact with `idb`.

It can be installed via pip:
```
pip3.6 install fb-idb
```
Note: The idb client requires python 3.6 or greater to be installed.

Please refer to [fbidb.io](http://fbidb.io/) for detailed installation instructions and a guided tour of idb.

Once installed, just run the list-targets command which will show you all the simulators installed on your system:

```
$ idb list-targets
...
iPhone X | 569C0F94-5D53-40D2-AF8F-F4AA5BAA7D5E | Shutdown | simulator | iOS 12.2 | x86_64 | No Companion Connected
iPhone Xs | 2A1C6A5A-0C67-46FD-B3F5-3CB42FFB38B5 | Shutdown | simulator | iOS 12.2 | x86_64 | No Companion Connected
iPhone Xs Max | D3CF178F-EF61-4CD3-BB3B-F5ECAD246310 | Shutdown | simulator | iOS 12.2 | x86_64 | No Companion Connected
iPhone Xʀ | 74064851-4B98-473A-8110-225202BB86F6 | Shutdown | simulator | iOS 12.2 | x86_64 | No Companion Connected
...
```

`list-apps` will show you all the apps installed in a simulator:

```
$ idb list-apps --udid 74064851-4B98-473A-8110-225202BB86F6
com.apple.Maps | Maps | system | x86_64 | Not running | Not Debuggable
com.apple.MobileSMS | MobileSMS | system | x86_64 | Not running | Not Debuggable
com.apple.mobileslideshow | MobileSlideShow | system | x86_64 | Not running | Not Debuggable
com.apple.mobilesafari | MobileSafari | system | x86_64 | Not running | Not Debuggable
```

`launch` will launch an application the application:

```
$ idb launch com.apple.mobilesafari
```

Head over [here](fbidb.io) for more details on what you can do with idb and the full list of commands.

## Building from Source

`idb` is made up of 2 parts.

To build the python part make sure you are in the root of the repo and run:

```
pip3 install .
```

To build the objective-c/c++ part:

```
open idb_companion.xcworkspace
```

This will open an xcode project that you can build and run.

## Documentation

Find the full documentation for this project at [fbidb.io](http://fbidb.io/)

## Contributing

We've released `idb` because it's a big part of how we scale iOS automation at Facebook. We hope that others will be able to benefit from the project where they may have needs that aren't currently serviced by the standard Xcode toolchain.

## Code of Conduct

Facebook has adopted a Code of Conduct that we expect project participants to adhere to. Please [read the full text](https://code.fb.com/codeofconduct) so that you can understand what actions will and will not be tolerated.

## Contributing Guide

Read our [contributing guide](.github/CONTRIBUTING.md) to learn about our development process.

## License

[`idb` is MIT-licensed](LICENSE).
