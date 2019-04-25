---
id: commands
title: Commands
---
## Starting idb

### starting a daemon
a daemon will be started automatically at port 9889 if one wasn't implicitly started.

```
idb daemon
```


| Argument | Description | Default
|----------|-------------|--------
|--daemon-port PORT | Port for the daemon to listen on | 9889
|--log {DEBUG,INFO,WARNING,ERROR,CRITICAL} | Set the log level | CRITICAL
|--reply-fd REPLY_FD | File descriptor to write port the daemon was started on |


### Starting a companion
on macs, we start a companion automatically

```
idb_companion --udid UDID
```

| Argument | Description | Default
|----------|-------------|--------
|--udid UDID | Specify the target device / simulator |
|--port PORT | Port to start on | 10880
|--grpc-port PORT | Port to start on | 10882
|--log-file-path PATH | Path to write a log file to e.g ./output.log | Logs to stdErr
|--device-set-path PATH | Path to the custom device set if used |
|--daemon-host HOST | Auto connect to a daemon |
|--daemon-host PORT | Auto connect to a daemon |
|--serving-host HOST | Hostname to report to the daemon |


## Commands
### General arguments
| Argument | Description | Default
|----------|-------------|--------
|--udid UDID | UDID of the target | If only one target is connected it'll use that one
|--log {DEBUG,INFO,WARNING,ERROR,CRITICAL} | Set the log level | CRITICAL
|--json | JSON structured output where applicable | False


## Apps

### List all the installed applications on a device

```
idb list-apps
...
com.apple.mobileslideshow | MobileSlideShow | system | x86_64
...
```

### Install a .app

```
idb install testApp.app
```

### Launch an app by bundle id

Environment variables that are prefixed with IDB_ will be passed through to the test run with that prefix removed, also any arguments appended to the end of the idb command will be supplied as arguments to the test run

```
idb launch com.facebook.callumryan.testApp
```


### Kill a running app

```
idb terminate com.facebook.callumryan.testApp
```

= Targets =

A target is a single device/simulator

### List connected targets

```
idb list-targets
```

### Connect to a target's idb companion

```
idb connect HOST PORT
idb connect TARGET_UDID (only works for local use. and it will spawn a companion automatically)
```

### disconnect from a target's idb companion

```
idb disconnect HOST PORT
idb disconnect TARGET_UDID
```

## Tests

### Install a .xctest bundle

```
idb xctest install testApp.app/Plugins/testAppTests.xctest
```

### List installed tests


```
idb xctest list
...
com.facebook.callumryan.testAppTests | testAppTests | x86_64
...
```

### List tests inside a bundle

```
idb xctest list-bundle com.facebook.myAppTests
```

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

### Run an app test=

```
idb xctest run app TEST_BUNDLE_ID APP_BUNDLE_ID
```

## Misc

### Log
Tail logs from a target, uses the standard log(1) stream arguments

```
idb log
```

### Push
Copy a file to inside an installed apps container

```
idb push ./myFile.txt com.facebook.myApp tmp
```

### Pull
Moves a file/folder from an apps container to your local machine

```
idb pull APP_BUNDLE_ID PATH_RELATIVE_TO_CONTAINER LOCAL_PATH_TO_COPY_TO
```

### Open a url

```
idb open https://facebook.com
```

### Clear the keychain

```
idb clear_keychain
```

### Set a simulators location

```
idb set_location LAT LONG
```

### Terminate Daemons

```
idb kill
```

### Boot
boots a simulator
```
idb boot UDID
```
