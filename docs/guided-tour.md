---
id: guided-tour
title: Guided Tour
---

## This is a quick start guide to show you a glimpse of what idb can do.

if you haven't installed idb already please refer to [installation](installation.md).

Let's start with finding out what simulators/devices are available on your mac.

```
idb list-targets
```

will print out all the simulators on your mac and all of the devices attached.

let's boot any one of them.

```
idb boot UDID
```

you can then try any of the commands below and make sure you pass --udid to run them with the correct simulator.

```
idb launch com.apple.Maps
idb record
idb log
```

Now let's try to run tests.

```
idb xctest install Fixtures/Binaries/iOSUnitTestFixture.xctest
```

will install the test bundle provided on the simulator

to verify that it's been installed correctly just run

```
idb xctest list
```

and then you can run the tests by issuing these commands. `run logic` would just run the logic tests while `run app` will run the app tests, `run ui` will run the ui tests

```
idb xctest run logic com.facebook.iOSUnitTestFixture
idb xctest run app com.facebook.iOSUnitTestFixture com.apple.Maps
```
