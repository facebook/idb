/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorDiagnosticsTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorDiagnosticsTests

- (void)assertFindsNeedle:(NSString *)needle fromHaystackBlock:( NSString *(^)(void) )block
{
  __block NSString *haystack = nil;
  BOOL foundLog = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
    haystack = block();
    return haystack != nil;
  }];
  if (!foundLog) {
    XCTFail(@"Failed to find haystack log");
    return;
  }

  [self assertNeedle:needle inHaystack:haystack];
}

- (void)testAppCrashLogIsFetched
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:self.tableSearchApplication];
  NSString *path = [[NSBundle bundleForClass: self.class] pathForResource:@"libShimulator" ofType:@"dylib"];
  FBApplicationLaunchConfiguration *configuration = [self.tableSearchAppLaunch injectingLibrary:path];
  FBApplicationLaunchConfiguration *appLaunch = [configuration withEnvironmentAdditions:@{@"SHIMULATOR_CRASH_AFTER" : @"1"}];

  NSError *error = nil;
  BOOL success = [simulator launchApplication:appLaunch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Shimulator sends an unrecognized selector to NSFileManager to cause a crash.
  // The CrashReporter service is a background service as it will symbolicate in a separate process.
  [self assertFindsNeedle:@"-[NSFileManager stringWithFormat:]" fromHaystackBlock:^ NSString * {
    return [[simulator.simulatorDiagnostics.userLaunchedProcessCrashesSinceLastLaunch firstObject] asString];
  }];
}

- (void)testSystemLog
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];

  [self assertFindsNeedle:@"syslogd" fromHaystackBlock:^ NSString * {
    return simulator.simulatorDiagnostics.syslog.asString;
  }];
}

- (void)testLaunchedApplicationLogs
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:self.tableSearchApplication];
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch.injectingShimulator;

  NSError *error = nil;
  BOOL success = [simulator launchApplication:appLaunch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertFindsNeedle:@"Shimulator" fromHaystackBlock:^ NSString * {
    return [[simulator.simulatorDiagnostics.launchedProcessLogs.allValues firstObject] asString];
  }];
}

- (void)testLaunchedApplicationLogsWithCustomLogFilePath
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSString *stdErrPath = [path stringByAppendingPathComponent:@"stderr.log"];
  NSString *stdOutPath = [path stringByAppendingPathComponent:@"stdout.log"];

  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration configurationWithStdOut:stdOutPath stdErr:stdErrPath error:nil];
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:self.tableSearchApplication];
  FBApplicationLaunchConfiguration *appLaunch = [[self.tableSearchAppLaunch withOutput:output] injectingShimulator];

  NSError *error = nil;
  BOOL success = [simulator launchApplication:appLaunch error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSFileManager *fileManager = [NSFileManager defaultManager];
  XCTAssertTrue([fileManager fileExistsAtPath:stdErrPath]);
  XCTAssertTrue([fileManager fileExistsAtPath:stdOutPath]);

  [self assertFindsNeedle:@"Shimulator" fromHaystackBlock:^ NSString * {
    NSString *stdErrContent = [NSString stringWithContentsOfFile:stdErrPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *stdOutContent = [NSString stringWithContentsOfFile:stdOutPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *combinedContent = [stdErrContent stringByAppendingString:stdOutContent];
    if (!combinedContent.length) {
      return nil;
    }
    return combinedContent;
  }];
}

- (void)testCreateStdErrDiagnosticForSimulator
{
  NSError *error;
  FBDiagnostic *stdErrDiagnostic = nil;
  FBDiagnostic *stdOutDiagnostic = nil;

  FBSimulator *simulator = [self assertObtainsSimulator];
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration defaultOutputToFile];
  FBApplicationLaunchConfiguration *appLaunch = [self.tableSearchAppLaunch withOutput:output];

  [appLaunch createStdErrDiagnosticForSimulator:simulator diagnosticOut:&stdErrDiagnostic error:&error];
  XCTAssertNil(error);

  [appLaunch createStdOutDiagnosticForSimulator:simulator diagnosticOut:&stdOutDiagnostic error:&error];
  XCTAssertNil(error);

  XCTAssertNotNil(stdErrDiagnostic.asPath);
  XCTAssertNotNil(stdOutDiagnostic.asPath);

  NSFileManager *fileManager = [NSFileManager defaultManager];
  XCTAssertTrue([fileManager fileExistsAtPath:stdErrDiagnostic.asPath]);
  XCTAssertTrue([fileManager fileExistsAtPath:stdOutDiagnostic.asPath]);
}

@end
