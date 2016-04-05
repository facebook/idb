# XCTestBootstrap
A Mac OS X library for launching XCTest & XCUITest and managing connection with testmanager daemon.

## Features
- Prepares XCTest bundle.
- Launches application and injects XCTest bundle.
- Opens and manages connection with testmanager daemon during the test.
- It works with iOS simulator & device tests.
- It works with Mac OSX tests.

## Usage
In order to use XCTestBootstrap you need to provide class that implements `<FBDeviceOperator>` supplying basic device instructions like install application, launch application etc.

A good example is [`FBSimulatorControlOperator`](https://github.com/facebook/FBSimulatorControl/blob/master/FBSimulatorControl/Interactions/FBSimulatorControlOperator.m)
and [`FBSimulatorInteraction+XCTest`](https://github.com/facebook/FBSimulatorControl/blob/master/FBSimulatorControl/Interactions/FBSimulatorInteraction%2BXCTest.m)\

```objc

  FBSimulatorTestPreparationStrategy *testPrepareStrategy =
  [FBSimulatorTestPreparationStrategy strategyWithTestRunnerBundleID:configuration.bundleID
                                                    testBundlePath:testBundlePath
                                                  workingDirectory:workingDirectory
                                                  ];
  FBSimulatorControlOperator *operator = [FBSimulatorControlOperator operatorWithSimulator:self.simulator];
  FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy strategyWithDeviceOperator:operator testPrepareStrategy:testPrepareStrategy logger:simulator.logger];
  NSError *innerError = nil;
  FBTestManager *testManager = [testRunStrategy startTestManagerWithAttributes:configuration.arguments environment:configuration.environment error:&innerError];
```

`FBTestManager` needs to be kept alive in order to keep test running.

## Contributing
See the [CONTRIBUTING](CONTRIBUTING) file for how to help out. There's plenty to work on the issues!

## License
[`XCTestBootstrap` is BSD-licensed](LICENSE). We also provide an additional [patent grant](PATENTS).
