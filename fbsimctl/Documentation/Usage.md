# Interface

A command passed to `fbsimctl` looks like the following:

```
fbsimctl [CONFIGURATION] [QUERY] [FORMAT] [ACTION]
```

## Configuration

These are flags and options that are provided to the `fbsimctl` process that define global constants. They alter the behaviour of `fbsimctl` as well as how it presents output.

- `--debug-logging` increases the verbosity of logging output. This can be helpful when you want to figure out what is going on when things go wrong.
- `--json` outputs linewise JSON to `stdout` instead of Human-Readable events to `stdout` and logging to `stderr`. 
- `--format=` Can be used to change how Simulators & Devices are reported when `--json` is not passed. For example `--format=%m%p` will print just the Device Model, followed by the OS Version.
- `--set /path/to/device-set` Will point `fbsimctl` at an alternative Simulator Device Set, with the provided Path. By default `fbsimctl` will use the 'Default Device Set' that is located at `~/Library/Developer/CoreSimulator/Devices`.

## Query

Every Action that `fbsimctl` executes can be applied to any number of iOS Targets. A Query can specify anywhere from a individual iOS Target to all the Targets that are currently available to the host. This power allows you to trivially automate a single Action against many targets at once.

- `--state=booted|shutdown|creating|booting|shutting-down` is a Query that will find targets that match a given state. You can specify multiple states by sequencing them: `--state=booted --state==booting`. Note that most `Actions` will apply only to booted targets.
- Providing a UDID like `044668F4-D4A6-49BC-8D56-F45B58314A7F` will target an individual Simulator UDID. This is similar to the way that Apple's `fbsimctl` functions.
- OS Versions can be supplied, such as `'iOS 9.3'`.
- Device Types can be supplied, such as 'iPad Air 2', 'iPhone 6s'.

Queries also can be combined. Combined queries operate on the intersection of the arguments. This is done by sequencing the queries one after another:

- `--state=booted 'iPhone 5' 'iPhone 5s'` will perform Actions against all Booted iPhone 5 and 5s Targets.
- `044668F4-D4A6-49BC-8D56-F45B58314A7F 40520A90-EFCB-489F-8BFB-FEC2FD02320E` will perform Actions against the targets with the two specified UDIDs
- `'iOS 10.0' 'iOS 9.3'` will perform Actions against all iOS Targets running iOS 10.0 or iOS 9.3. Note that this applies for all targets, no matter the state that they are in.

All non-destructive actions in `fbsimctl` have implicit default Queries, which means in many cases you will not need to provide a Query at all. This can really help you out if you just want to quickly execute a few Actions and move on. The Default Queries will target the sensible default for the first Action that you provide. For example the `install` Action will default to running against all booted Simulators.

## Actions

Actions expose the core features of `fbsimctl` and there are a great number of them. There is some overlap with Apple's `simctl`, but `fbsimctl` also provides some actions that `simctl` does not.A

- `approve [APPLICATION-BUNDLE-ID ...]` will approve the location services for Application Bundle Identifiers. This is useful if you want to bypass the Location Services dialog before you launch an App. This will only function on Simulators that are in the shutdown state.
- `boot [BOOT-CONFIGURATION]` will boot a Simulator. There are many flags that can be provided after the `boot` string. These flags are discussed later on.
- `create [SIMULATOR-CONFIGURATION]` will create a Simulators. There are a number of flags that can be provided here to specify the kind of Simulator that will be created. These flags are discussed later on.
- `diagonse [DIAGNOSTIC-CONFIGURATION]` will fetch diagnostic information and logs from Simulators. The output and the kinds of information presented is discussed later on.
- `delete` will delete a Simulator. There is no default query for this Action as it is destructive, so you must specify a query before the delete string. `delete` will not fail on booted Simulators like `fbsimctl`, as it will ensure that the Simulator is in a shutdown state before attempting deletion. Make sure to fetch any important logs and data with `diagnose` before performing this action.
- `install [APPLICATION-PATH]` will install an Application on Simulators. It will only work on booted Simulators. As such, the default Query will target booted Simulators.
- `erase` will erase Simulators. There is no default query for this Action as it is destructive, so you must specify a query before the delete string. `erase` will not fail on booted Simulators like `fbsimctl`, as it will ensure that the Simulator is in a shutdown state before attempting to erase.
- `launch [APPLICATION-BUNDLE-ID|EXECUTABLE-PATH] --arg1 --arg2` will launch an Application or spawn an executable on the booted Simulators. If Application Bundle ID is provided, the Application must be Installed. If a executable path is provided, a daemon will be launched on the Simulator instead. Any argument provided after the Bundle ID or Executable will be provided to the launched process as an argument. Calling `launch` for an Application that is currently running will bring it to the foreground. Multiple daemons with the same executable path can run on a Simulator at the same time. There is also the `relaunch` command, which will ensure that the Application is 'Cold Started', that is to say it will be terminated before re-launching.
- `list` will print a description of all iOS Targets in specified by the Query. By default this will find all Simulators and Devices on the host.
- `list-apps` will print a description of the installed Applications on Simulators.
- `listen` allows an HTTP Server or Interactive Shell to be started. Flags and behaviour here is discussed later on.
-  `open [URL]` will open a URL on the Simulator.
- `record [start|stop]` will start or stop video recording. Video recording is discussed later on.
- `shutdown` will shutdown any booted Simulator. `fbsimctl` has remediation for many circumstances that would cause `simctl` to fail.
- `terminate [APPLICATION-BUNDLE-ID]` will terminate an Application by Bundle Identifier. Targets booted Simulators by default.
- `upload [PATH ...]` will upload resources to a Simulator specified by file paths. In the case of videos and photos, the resources will be placed in the camera roll. With other files, they will be placed in an 'Auxillary Directory' within the Simulator's Root directory. By default this will target booted iOS Simulators.
- `watchdog-override [TIMEOUT-SECONDS] [APPLICATION-BUNDLE-ID ...]` will set the watchdog timer that iOS uses when launching an Application. Multiple Applications can be specified after a number specifying the timeout in seconds. This should be executed on Simulators *before* booting them, as it is read by Springboard on launch.
- `set_location [LATITUDE] [LONGITUDE]` will set custom location.

## Creation

Simulators can be created with the `create` command. There are a few options here that should be placed after the `create` argument:

- `--all-missing-defaults` will create all the 'Default Simulators' that are missig for the current Simulator set. This means that a Simulator will be created for each available iOS Version & Device Combination.
- A Single Simulator can be defined by supplying an OS Version & Device Type. For example `create 'iOS 9.1' 'iPhone 6s'` will create an iPhone 6s running iOS 9.1. If Device Type is not specified it will default to an iPhone 6. If an OS Version is not specified it will default to the newest available OS Version for the current version of Xcode.

## Booting

When booting a Simulator, a number of arguments can be provided to alter the behaviour of the booting process. Options can be sequenced.

- `--locale es_ES` will boot the Simulator in the `en_ES` locale.
- `--scale=25|50|75|100` will boot the Simulator Application

There are two ways of booting a Simulator: 
- If you supply no arguments, the Simulator will be booted with the `Simulator.app` for the curent version of Xcode. This will allow the user to interact with the UI in the familiar Application.
- If you supply the `--direct-launch` argument, the Simulator will be launched from `CoreSimulator`. This is the way that Apple's `simctl` will launch Simulators. The Simulator is launched in a 'headless' way, which means that there is no User Inferface. However, `fbsimctl` will connect a Framebuffer to the Simulator as it is Booting. This enables Video Recording, providing that the `fbsimctl` process is kept alive. Booting simulators 'directly' can also be substantially more performant than using `Simulator.app`.

## Diagnostics

The `diagnose` command can be used to fetch useful diagnostic information from any Simulator. When `fbsimctl` creates any diagnostic information, it also makes it available to the diagnose command. By default `diagnose` will target all iOS Targets.

To get a list of all the diagnostics available for booted Simulators:
```
$ fbsimctl --state=booted diagnose
# Information about each log is printed to a single line
C3F0183E-B497-4916-9E99-82FB8A842624 | iPhone 5s | Booted | iPhone 5s | iOS 8.4: diagnostic: Path Log Short Name 'system_log' | Content 1 | Path /Users/user/Library/Logs/CoreSimulator/C3F0183E-B497-4916-9E99-82FB8A842624/system.log
C3F0183E-B497-4916-9E99-82FB8A842624 | iPhone 5s | Booted | iPhone 5s | iOS 8.4: diagnostic: Path Log Short Name 'coresimulator' | Content 1 | Path /Users/user/Library/Logs/CoreSimulator/CoreSimulator.log
C3F0183E-B497-4916-9E99-82FB8A842624 | iPhone 5s | Booted | iPhone 5s | iOS 8.4: diagnostic: Path Log Short Name 'launchd_bootstrap' | Content 1 | Path /Users/user/Library/Developer/CoreSimulator/Devices/C3F0183E-B497-4916-9E99-82FB8A842624/data/var/run/launchd_bootstrap.plist
# Find an read the system log instantly, page it into less
$ fbsimctl --state=booted diagnose | grep system_log | awk '{print $NF}' | xargs less
```

## `listen`

The `listen` action of `fbsimctl` will keep the `fbsimctl` process running, until a `SIGINT`, `SIGHUP` or `SIGTERM` is sent to the process. This can be used to keep a Simulator alive that was previously launched with `--direct-launch`. 

Additionally, it is possible to listen on an interface for incoming commands:

- `listen --stdin` with no arguments will accept commands over `stdin`. A command will interpreted, when a newline character is sent.
- `listen --http [PORT-NUMBER]` will start a HTTP server on `PORT-NUMBER`. Many of the common `fbsimctl` actions are exposed with individual endpoints.

## Video Recording with Xcode 8

Since Xcode 8, `fbsimctl` can record the video of any booted Simulator, regardless of where it was booted. There's a handy script called [`fbsimrecord` for doing this](../Scripts/README.md). This script is included in the standard install for convenience and quick recall. You an specify the output path of the video, if you wish:

```
$ fbsimctl record start /tmp/Recorded.mp4
```

The location of the video file for each booted simulator will be printed to `stdout`. This makes it easy to combine with `open(1)`, `cp(1)` or any other command for further automation. The script itself simple so you can automate in any way that you choose.

## Video Recording with Xcode 7

In Xcode 7, it's not quite a simple to record a video as in Xcode 8. In order to record a video for Simulators from Xcode 7, you'll need to boot the Simulator 'Headlessly' and start recording as the Simulator boots. Fortunately, `fbsimctl` makes this possible with it's support of chaining actions inside the same process. Chaining is done through a `--` argument to separate each action:

```
# Boot a Simulator headlessly, start video recording.
$ fbsimctl F0F071BB-8775-472C-8378-262BB6D31212 boot --direct-launch \
  -- record start \
  -- listen --http 8090 \
  -- shutdown \
  -- diagnose
```

This will create a `fbsimctl` process that boots, starts video recording then opens a HTTP Server on Port 8090. When a `SIGHUP` is sent to the process, it will shutdown the Simulator and print the location of all availiable diagnostics for the Simulator. This will include a path to the video recording of the Simulator.

## Output

By default, `fbsimctl` outputs event-based information to `stdout`, which represents the lifecyle of a command. `fbsimctl` also hooks into the logging provided by the `FBSimulatorControl` Framework and outputs this to `stderr`. By default a 'low verbosity' mode is used for logs written to `stderr`. If you wish to increase this level, you can pass the `--debug-logging` flag.

Automating Command Line Appliations can be a pain if the output is intended to be read by humans instead of by machines. If you wish to automate `fbsimctl` and extract information from the output, you may want to use the `--json` flag, which will print line-terminated JSON events to `stdout`. Each event has an `event_name`, `event_type` and a `subject`.

