# `fbsimctl`

`fbsimctl` is a command line interface to the `FBSimulatorControl` Framework. It intends to expose the core features of the `FBSimulatorControl` framework with a syntax that accommodates many common automation scenarios.

`fbsimctl` can be used to:
- Remotely control a Simulator via a HTTP Wire Protocol.
- Install & Launch Applications or Spawn Processes.
- Record Videos of the Simulator's Screen.
- Fetch diagnostic logs associated with a Simulator.
- Easily perform the same task over multiple Simulators at once.
- Provide Machine-Readable output with JSON Reporting, enables [easier automation from any language](https://github.com/facebook/FBSimulatorControl/blob/master/fbsimctl/cli-tests/tests.py).
- Launch `XCTest` bundles for [WebDriverAgent](https://github.com/facebook/WebDriverAgent/wiki/Starting-WebDriverAgent)

## Examples

To list all devices in the default 'Device Set':
```bash
$ fbsimctl list
# List output is sent to stdout
F0F071BB-8775-472C-8378-262BB6D31212 | iPhone 5 | Shutdown | iPhone 5 | iOS 8.4
...
48A99DA0-11AB-4219-91F6-A43D7024E2E8 | iPad Pro | Shutdown | iPad Pro | iOS 9.3
```

Boot some iPhones. Two at once!
```bash
$ fbsimctl F0F071BB-8775-472C-8378-262BB6D31212 044668F4-D4A6-49BC-8D56-F45B58314A7F boot
...
044668F4-D4A6-49BC-8D56-F45B58314A7F | iPhone 5 | Booted | iPhone 5 | iOS 9.3: launch: Bridge: Framebuffer ((null)) | HID (null) | Simulator Bridge: Connected
```

Installing and Launching an Application will apply to the Simulators that are booted:
```bash
$ fbsimctl install SomeApp.app
...
$ fbsimctl launch com.facebook.SomeApp
```

Shut all Simulators Down. Note that `fbsimctl` will automatically choose to shutdown all Simulators that are not already Shutdown:
```bash
$ fbsimctl shutdown
F0F071BB-8775-472C-8378-262BB6D31212 | iPhone 5 | Shutting Down | iPhone 5 | iOS 8.4: state: Shutting Down
F0F071BB-8775-472C-8378-262BB6D31212 | iPhone 5 | Shutdown | iPhone 5 | iOS 8.4: state: Shutdown
044668F4-D4A6-49BC-8D56-F45B58314A7F | iPhone 5 | Shutting Down | iPhone 5 | iOS 9.3: state: Shutting Down
044668F4-D4A6-49BC-8D56-F45B58314A7F | iPhone 5 | Shutdown | iPhone 5 | iOS 9.3: state: Shutdown
```

Fetching the System Log for a booted Simulator is easy. This works great with pipes!
```bash
fbsimctl --state=booted diagnose | grep system_log | awk '{print $NF}' | xargs less
```

Chain commands together, each action will be performed in sequence:
```bash
# Actions can be chained together with --
$ fbsimctl F0F071BB-8775-472C-8378-262BB6D31212 boot --direct-launch \
  -- record start \
  -- listen --http 8090 \
  -- shutdown \
  -- diagnose
...
Simulator Did launch => Process launchd_sim | PID 63988
...
Listen Started: HTTP: Port 8090
# Send a Ctrl-C the listen action will proceed to the next in the sequence.
SIGINT 2
Listen Ended: HTTP: Port 8090
..
Short Name 'video' | Content 1 | Path /Users/lawrencelomax/Library/Developer/CoreSimulator/Devices/F0F071BB-8775-472C-8378-262BB6D31212/data/fbsimulatorcontrol/diagnostics/video.mp4
```

More detailed documentation of all the features, is in the [Usage Document](Documentation/Usage.md).

## Installation

The quickest way to get going with `fbsimctl` is to use the [Homebrew Formula](http://brew.sh). The Homebrew formula is part of [Faceboook's Homebrew Tap](https://github.com/facebook/homebrew-fb).

```bash
# Get the Facebook Tap.
brew tap facebook/fb
# Install fbsimctl from master
brew install fbsimctl --HEAD
```

When building `fbsimctl`, you must be using Xcode 8.0 or greater. More [detailed instructions for a custom installation is also available.](Documentation/Installation.md)
