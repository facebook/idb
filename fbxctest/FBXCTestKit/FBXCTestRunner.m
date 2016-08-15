/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRunner.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBJSONTestReporter.h"
#import "FBTestRunConfiguration.h"
#import "FBXCTestError.h"
#import "FBXCTestReporterAdapter.h"

@interface FBXCTestRunner ()
@property (nonatomic, strong) FBTestRunConfiguration *configuration;
@end

@implementation FBXCTestRunner

+ (instancetype)testRunnerWithConfiguration:(FBTestRunConfiguration *)configuration
{
  FBXCTestRunner *runner = [self new];
  runner->_configuration = configuration;
  return runner;
}

- (BOOL)executeTestsWithError:(NSError **)error
{
  FBSimulatorControl *simulatorControl = [self createSimulatorControlWithError:error];
  if (!simulatorControl) {
    return NO;
  }
  FBSimulator *simulator = [simulatorControl.pool allocateSimulatorWithConfiguration:self.configuration.targetDeviceConfiguration
                                                                             options:FBSimulatorAllocationOptionsCreate
                                                                               error:error];
  if (!simulator) {
    return NO;
  }
  if (![self runTestWithSimulator:simulator error:error]) {
    [simulatorControl.pool freeSimulator:simulator error:nil];
    return NO;
  }
  if (![simulatorControl.pool freeSimulator:simulator error:error]) {
    return NO;
  }
  if (![self.configuration.reporter printReportWithError:error]) {
    return NO;
  }
  return YES;
}

- (FBSimulatorControl *)createSimulatorControlWithError:(NSError **)error
{
  NSString *deviceSetPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"sim"];
  FBSimulatorControlConfiguration *simulatorControlConfiguration =
  [FBSimulatorControlConfiguration configurationWithDeviceSetPath:deviceSetPath options:0];
  return [FBSimulatorControl withConfiguration:simulatorControlConfiguration logger:self.configuration.logger error:error];
}

- (BOOL)runTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (self.configuration.runnerAppPath == nil) {
    return [self runLogicTestWithSimulator:simulator error:error];
  }

  FBSimulatorLaunchConfiguration *simulatorLaunchConfiguration = [FBSimulatorLaunchConfiguration defaultConfiguration];
  FBInteraction *launchInteraction =
  [[simulator.interact
    prepareForLaunch:simulatorLaunchConfiguration]
   bootSimulator:simulatorLaunchConfiguration];

  if (![launchInteraction perform:error]) {
    [self.configuration.logger logFormat:@"Failed to boot simulator: %@", *error];
    return NO;
  }

  if (![self runApplicationTestWithSimulator:simulator error:error]) {
    [[simulator.interact shutdownSimulator] perform:nil];
    return NO;
  }

  if (![[simulator.interact shutdownSimulator] perform:error]) {
    [self.configuration.logger logFormat:@"Failed to shutdown simulator: %@", *error];
    return NO;
  }

  return YES;
}

- (BOOL)runLogicTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  [self.configuration.reporter didBeginExecutingTestPlan];

  NSString *xctestPath = [FBControlCoreGlobalConfiguration.developerDirectory
                          stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"];
  NSString *simctlPath = [FBControlCoreGlobalConfiguration.developerDirectory
                          stringByAppendingPathComponent:@"usr/bin/simctl"];
  NSString *executablePath = [NSProcessInfo processInfo].arguments[0];
  if (!executablePath.isAbsolutePath) {
    executablePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingString:executablePath];
  }
  executablePath = [executablePath stringByStandardizingPath];
  NSString *installationRoot = executablePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
  NSString *otestShimPath = [installationRoot stringByAppendingPathComponent:@"lib/otest-shim-ios.dylib"];

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = simctlPath;
  task.arguments = @[@"--set", simulator.deviceSetPath, @"spawn", simulator.udid, xctestPath, @"-XCTest", @"All", self.configuration.testBundlePath];
  NSMutableDictionary *environment = [NSProcessInfo processInfo].environment.mutableCopy;
  environment[@"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES"] = otestShimPath;
  task.environment = environment.copy;
  task.standardOutput = [NSFileHandle fileHandleWithStandardOutput];
  task.standardError = [NSFileHandle fileHandleWithNullDevice];
  [task launch];
  [task waitUntilExit];

  if (task.terminationStatus != 0 && task.terminationStatus != 1) {
    return [[FBXCTestError describeFormat:@"Subprocess exited with code %d: %@ %@", task.terminationStatus, task.launchPath, task.arguments] failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

- (BOOL)runApplicationTestWithSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  FBApplicationDescriptor *testRunnerApp = [FBApplicationDescriptor applicationWithPath:self.configuration.runnerAppPath error:error];
  if (!testRunnerApp) {
    [self.configuration.logger logFormat:@"Failed to open test runner application: %@", *error];
    return NO;
  }

  if (![[simulator.interact installApplication:testRunnerApp] perform:error]) {
    [self.configuration.logger logFormat:@"Failed to install test runner application: %@", *error];
    return NO;
  }

  FBApplicationLaunchConfiguration *appLaunch =
  [FBApplicationLaunchConfiguration configurationWithApplication:testRunnerApp
                                                       arguments:@[]
                                                     environment:@{}
                                                         options:0
   ];

  NSString *workingDirectoryPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"tmp"];
  FBInteraction *interaction =
  [[simulator.interact
    startTestRunnerLaunchConfiguration:appLaunch
    testBundlePath:self.configuration.testBundlePath
    reporter:[FBXCTestReporterAdapter adapterWithReporter:self.configuration.reporter]
    workingDirectory:workingDirectoryPath
    ] waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:5000];


  if (![interaction perform:error]) {
    [self.configuration.logger logFormat:@"Failed to execute test bundle: %@", *error];
    return NO;
  }
  return YES;
}

@end
