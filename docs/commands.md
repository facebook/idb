---
id: commands
title: Commands
---
### Reset Idb

```
idb kill
```

idb stores information about available companions in a local file. this command clears these files and kills the idb notifier if one is running.


### Starting a companion
```
idb_companion --udid UDID
```
Starts up a companion process for a target specified by its UDID.
On macs idb can spawn a companion automatically on connect


| Argument | Description | Default
|----------|-------------|--------
|--udid UDID | Specify the target device / simulator |
|--port PORT | Port to start on | 10882
|--log-file-path PATH | Path to write a log file to e.g ./output.log | Logs to stdErr
|--device-set-path PATH | Path to the custom device set if used |
|--daemon-host HOST | Auto connect to a daemon |
|--daemon-host PORT | Auto connect to a daemon |
|--serving-host HOST | Hostname to report to the daemon |


### Starting a notifier
```
idb_companion --notify FILE_PATH
```
Starts up a companion process in the notifier mode.
in this mode the companion will find out what simulators/devices are available and write that output to the file path specified.
A notifier is always spawned automatically if the idb cli is called on a mac.


### Boot a simulator

```
idb boot UDID
```

When running locally idb can boot an installed simulator.
To see a list of the available targets try `idb list-targets`

### Connect a target
To use the idb client with a target, first its companion must be connected.

To connect to an existing companion run:
```
idb connect COMPANION_HOST COMPANION_PORT
```

In the local case you can connect via UDID, idb will also spawn a companion for you.
```
idb connect TARGET_UDID
```

### Disconnect a target

```
idb disconnect COMPANION_HOST COMPANION_PORT
idb disconnect TARGET_UDID
```

Tell idb to forget about a specific companion. This will not kill the companion.

### List connected targets

```
idb list-targets
```

List all of the targets idb can currently communicate with.

This will be all targets that have been connected through `idb connect` as well as any that could be booted if idb is running locally.


## Commands
### General arguments
| Argument | Description | Default
|----------|-------------|--------
|--udid UDID | UDID of the target | If only one target is connected it'll use that one
|--log {DEBUG,INFO,WARNING,ERROR,CRITICAL} | Set the log level | CRITICAL
|--json | JSON structured output where applicable | False


## Apps

### List apps

```
idb list-apps
```
Lists the targets installed applications and their metadata, including:
- Bundle ID
- Name
- Install type (user, system)
- Architectures
- Running status
- Debuggable status

### Install an app

```
idb install testApp.app
```
Installs the given .app or .ipa.

### Launch an app

```
idb launch com.apple.Maps
```

Any environment variables that are prefixed with IDB_ will be set on the launched app, with that prefix removed.

Custom launch arguments can also be provided by appending them to the end of the command.

By default `idb launch` will fail if the app is already running, this can be overruled with `-f/--foreground-if-running`.

To tail the output of the launched process provide the `-w/--wait-for` flag. The stdout and stderr of the app will be streamed back until the app exits, or is killed with `^C`.

### Kill a running app

```
idb terminate com.apple.Maps
```

Kills an app with the given bundle ID.

### Uninstalling an app
```
idb uninstall com.facebook.Facebook
```
Removes an app from the target.

## Tests

### Install a test bundle

```
idb xctest install testApp.app/Plugins/testAppTests.xctest
```

Before a test can be run through idb it must first be installed on the target.

Both `.xctest` and `.xctestrun` files can be installed with this command.

### List installed tests

```
idb xctest list
```

Lists all of the tests installed on a target.

### List tests inside a bundle

```
idb xctest list-bundle com.facebook.myAppTests
```

Lists all of the individual tests inside a test bundle.

### Running tests

Environment variables that are prefixed with IDB_ will be passed through to the test run with that prefix removed, also any arguments appended to the end of the idb command will be supplied as arguments to the test run

=## Run a UI test=

Note that APP_BUNDLE_ID should be that of the app you want to test, not the 'Runner' app xcode produces.
TEST_HOST_APP_BUNDLE_ID is the id of 'Runner' app.

```
idb xctest run ui TEST_BUNDLE_ID APP_BUNDLE_ID TEST_HOST_APP_BUNDLE_ID
```

### Run a logic test

Logic tests allow you to run tests on iOS Simulators that don't need an app's environment to happen (e.g.: Unit tests on libraries)

```
idb xctest run logic TEST_BUNDLE_ID
```

### Run an app test

```
idb xctest run app TEST_BUNDLE_ID APP_BUNDLE_ID
```

## Debug an app
### Starting a debug session

```
idb debugserver start BUNDLE_ID
```

Starts a debug session


### Stop a debug session

```
idb debugserver stop
```

Stops a running debug session.

### Information about a debug session

```
idb debugserver status
```

Display metadata about any running debug sessions.


## File commands

The `idb file` commands allow for managing files on a target, or moving them to/from a remote host.

All paths on a target are relative to a specific applications data container.

### Copy a file to a target
```
idb file push src1.jpg src2.jpg dest_1 --bundle-id BUNDLE_ID
```
Copies files from this host to an apps data container at the specified path.


### Fetch a file form a target
```
idb file pull src.txt dest.txt --bundle-id BUNDLE_ID
```
Copies a file from an apps data container to the host machine.

### Move a file between apps
```
idb file mv src1.jpg src2.jpg dest_1 --bundle-id BUNDLE_ID
```

Move source file(s) from one location in an apps data container to a different path in the same container.


### Make a new directory
```
idb file mkdir FOLDER_NAME --bundle-id BUNDLE_ID
```

Creates a new folder within the apps data container.

### Remove a path on a target
```
idb file rm PATH_A PATH_B --bundle-id BUNDLE_ID
```
Removes the specified paths within an apps data container.

If a folder is specified to be deleted, all of its contents will be removed recursively.

### List a path on a target
```
idb file ls PATH --bundle-id BUNDLE_ID
```
Returns a list of all the files present at the given path within an apps data container.


## Interact

For simulators we provide a handful of commands for emulating HID events.

### Tap
```
idb ui tap X Y
```
Taps a location on the screen specified in the points coordinate system.
The tap duration can be set with `--duration`

### Swipe
```
idb ui swipe X_START Y_START X_END Y_END
```
Swipes from the specified start point to the end.
By default this will be done by a touch down at the start point, followed by moving 10 points at a time until the end point is reached. The size of each step can be specified with `--delta`.

### Press a button
```
idb ui button {APPLE_PAY,HOME,LOCK,SIDE_BUTTON,SIRI}
```
Simulates a press of the specified button.
The press duration can be set with `--duration`.

### Inputting text
```
idb ui text "some text"
```
Types the specified text into the target.

```
idb ui key 4
```
Simulates the press of a key specified by its keycode.
The key presses duration can be set with `--duration`.


```
idb ui key-sequence 4 5 6
```
Inputs multiple key events sequentially.


## Accessibility info

### Describe the whole screen
```
idb ui describe-all
```
Returns a JSON formatted list of all the elements currently on screen, including their bounds and accessibility information.


### Describe a point
```
idb ui describe-point X Y
```
Returns JSON formatted information about a specific point on the screen, if an element exists there.



## Misc

### Describe a target
```
idb describe
```

Returns metadata about the specified target, including:
- UDID
- Name
- Screen dimensions and density
- State (booted/...)
- Type (simulator/device)
- iOS version
- Architecture
- Information about its companion

### Focus a simulators window
```
idb focus
```
Brings a simulators window to the foreground.

### Install a .dylib
```
idb dylib install test.dylib
```
Installs a `.dylib` on the target. This can then be injected into apps on launch.


### Instruments
```
idb instruments TEMPLATE
```
Starts instruments running connected to the target

### Record a video
```
idb record video OUTPUT_MP4
```
Starts recording the targets screen, outputting the content to the specified path. The recording can be stopped by pressing `^C`.

### Log
```
idb log
```

Tail logs from a target, uses the standard log(1) stream arguments


### Open a url

```
idb open https://facebook.com
```

Opens the specified URL on the target.
This works both with web addresses and URL schemes present on the target.

### Clear the keychain

```
idb clear_keychain
```

For simulators idb can clear the entire keychain.

### Set a simulators location

```
idb set_location LAT LONG
```

Overrides a simulators location to the latitude, longitude pair specified.

### Add media

```
idb add-media cat.jpg dog.mov
```

Files supplied to this command will be placed in the targets camera roll.
Most common image and video file formats are supported.

### Approve
```
idb approve com.apple.Maps photos camera
```

For simulators idb can programmatically approve permission for an app.
Currently idb can approve:
- `photos` - Permission to view the camera roll
- `camera` - Permission to access the camera
- `contacts` - Permission to access the targets contacts

### Add contacts
```
idb contacts update db.sqlite
```

For simulators idb can overwrite the simulators contacts db.


## Crash logs

idb includes several commands for fetching and managing a targets crash logs.

### List crash logs

```
idb crash list
```

Fetches a list of crash logs present on the target.
The results can be filtered by providing `--before/--since/--bundle-id`.

### Fetch a crash log

```
idb crash show CRASH_NAME
```

Fetches the crash log with the specified name

### Delete crash logs
```
idb crash delete CRASH_NAME
idb crash delete --before/--since/--all X
```

Deletes crash logs, either specified by name or all those matching the provided filters  `--before/--since/--bundle-id/--all`.
