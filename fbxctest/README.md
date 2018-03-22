# `fbxctest`

`fbxctest` is an experimental test runner for running iOS testing bundles for the iOS Simulator Platform. `fbxctest` will provide the following features:

- Structured Output of Test Results
- Support for concurrent running against Simulators.
- A Test Runner independent of a Full Build Chain.

Please note that not all features are implemented at the present time. For more information, consult the [Details Document.](Documentation/Details.md)

# What's new in this fork?

- `fbxctest` streams the events while running tests, instead of printing all collected events after tests have finished running.
- It also streams some errors in JSON format, allowing the invoker to restart `fbxctest` as needed.
- A bit better logging foe debugging purposes.
- For UI tests, `fbxctest` accepts multiple `-only` arguments so you can run a given set of tests only, without restarting simulator for each test.
- `XCTestConfiguration` plist is created with better module name (replaces `-` inside bundle name with `_` as this is what Xcode does).
- There is an option to apply keyboard and localization settings to newly created simulator before booting it and running tests: `-simulator-localization-settings`. It accepts a path to JSON file with the following sample contents:

```
{
  "locale_identifier": "ru_US",
  "keyboards": ["ru_RU@sw=Russian;hw=Automatic", "en_US@sw=QWERTY;hw=Automatic"],
  "passcode_keyboards": ["ru_RU@sw=Russian;hw=Automatic", "en_US@sw=QWERTY;hw=Automatic"],
  "languages": ["ru-US", "en", "ru-RU"],
  "adding_emoji_keybord_handled": true,
  "enable_keyboard_expansion": true,
  "did_show_international_info_alert": true
}
```

- There is an option to extend watchdog timeout for the tests: `-watchdog-settings`. It accepts a path to JSON with the following sample content:

```json
{
    "bundle_ids": [
        "com.example.app", 
        "com.apple.test.ExampleAppUITests-Runner"
    ],
    "timeout": 60
}
```

- Generally there is an API that allows you to preconfigure Simulator contents and state prior booting: `FBXCTestSimulatorConfigurator`.

- To record a video of all tests that ran, pass the option `-video /path/to/video.mp4`

- To store the oslog, pass the option `-oslog /path/to/oslog_output.log`

- To store the runner's app logs, pass `-testlog /path/to/runner_logs.log`

- There is an ability to override some types of hardcoded timeouts. This helps if you are running multiple simulators on the similar machine. The envs are: 

  - `FB_BUNDLE_READY_TIMEOUT` - helps on slow runtimes like iOS 9 when bundle with multiple frameworks may start slowly even if you override watchdog settings, 
  - `FB_CRASH_CHECK_WAIT_LIMIT`,
  - `FBCONTROLCORE_FAST_TIMEOUT`,
  - `FBCONTROLCORE_REGULAR_TIMEOUT`,
  - `FBCONTROLCORE_SLOW_TIMEOUT`

- Added ability to run and test multiple applications

    You can append the value of argument `-uiTest`, it is a colon-separated list, fourth and latter components are paths to bundles of applications.

    Example: `-uiTest /Tests.xctest:/Tests-Runner.app:/Your.app:/YourOther.app:/Another.app`

    This is done by setting `testApplicationDependencies` of `XCTestConfiguration`.
