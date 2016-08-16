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
#import <sys/types.h>
#import <sys/stat.h>
#import <XCTestBootstrap/FBTestManagerResultSummary.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBJSONTestReporter.h"
#import "FBMultiFileReader.h"
#import "FBLineReader.h"
#import "FBTestRunConfiguration.h"
#import "FBXCTestError.h"
#import "FBXCTestReporterAdapter.h"
#import "FBXCTestLogger.h"
#import "FBApplicationTestRunner.h"

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
  if (self.configuration.runWithoutSimulator) {
    if (self.configuration.runnerAppPath != nil) {
      return [[FBXCTestError describe:@"Application tests are not supported on OS X."] failBool:error];
    }

    if (self.configuration.listTestsOnly) {
      if (![self listTestsWithError:error]) {
        return NO;
      }

      if (![self.configuration.reporter printReportWithError:error]) {
        return NO;
      }

      return YES;
    }

    if (![self runLogicTestWithSimulator:nil error:error]) {
      return NO;
    }

    if (![self.configuration.reporter printReportWithError:error]) {
      return NO;
    }

    return YES;
  }

  if (self.configuration.listTestsOnly) {
    return [[FBXCTestError describe:@"Listing tests is only supported for macosx tests."] failBool:error];
  }

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

  if (self.configuration.testFilter != nil) {
    return [[FBXCTestError describe:@"Test filtering is only supported for logic tests."] failBool:error];
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

  if (![[FBApplicationTestRunner withSimulator:simulator configuration:self.configuration] runTestsWithError:error]) {
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

  NSString *xctestPath = [self xctestPathForSimulator:simulator];
  NSString *simctlPath = [FBControlCoreGlobalConfiguration.developerDirectory
                          stringByAppendingPathComponent:@"usr/bin/simctl"];
  NSString *installationRoot = [self fbxctestInstallationRoot];
  NSString *otestShimPath;
  if (simulator == nil) {
    otestShimPath = [installationRoot stringByAppendingPathComponent:@"lib/otest-shim-osx.dylib"];
  } else {
    otestShimPath = [installationRoot stringByAppendingPathComponent:@"lib/otest-shim-ios.dylib"];
  }
  NSString *otestShimOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"shim-output-pipe"];

  if (mkfifo([otestShimOutputPath UTF8String], S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestShimOutputPath] causedBy:posixError] failBool:error];
  }

  NSPipe *testOutputPipe = [NSPipe pipe];

  NSTask *task = [[NSTask alloc] init];
  NSString *testSpecifier;
  if (self.configuration.testFilter != nil) {
    testSpecifier = self.configuration.testFilter;
  } else {
    testSpecifier = @"All";
  }
  if (simulator == nil) {
    task.launchPath = xctestPath;
    task.arguments = @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];
  } else {
    task.launchPath = simctlPath;
    task.arguments = @[@"--set", simulator.deviceSetPath, @"spawn", simulator.udid, xctestPath, @"-XCTest", testSpecifier, self.configuration.testBundlePath];
  }
  task.environment = [self buildEnvironmentWithEntries:@{
                                                         @"DYLD_INSERT_LIBRARIES": otestShimPath,
                                                         @"OTEST_SHIM_STDOUT_FILE": otestShimOutputPath,
                                                         }
                                    targetingSimulator:simulator != nil];
  task.standardOutput = testOutputPipe.fileHandleForWriting;
  task.standardError = testOutputPipe.fileHandleForWriting;
  [task launch];

  [testOutputPipe.fileHandleForWriting closeFile];

  NSFileHandle *otestShimOutputHandle = [NSFileHandle fileHandleForReadingAtPath:otestShimOutputPath];
  if (otestShimOutputHandle == nil) {
    return [[FBXCTestError describeFormat:@"Failed to open fifo for reading: %@", otestShimOutputPath] failBool:error];
  }

  FBMultiFileReader *multiReader = [FBMultiFileReader fileReader];

  FBLineReader *otestLineReader = [FBLineReader lineReaderWithConsumer:^(NSString *line){
    if ([line length] == 0) {
      return;
    }
    NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
    if (event == nil) {
      NSLog(@"Received unexpected output from otest-shim:\n%@", line);
    }
    [self.configuration.reporter handleExternalEvent:event];
  }];
  if (![multiReader
        addFileHandle:otestShimOutputHandle
        withConsumer:^(NSData *data) {
          [otestLineReader consumeData:data];
        }
        error:error]) {
    return NO;
  }

  FBLineReader *testOutputLineReader = [FBLineReader lineReaderWithConsumer:^(NSString *line){
    [self.configuration.reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  if (![multiReader
        addFileHandle:testOutputPipe.fileHandleForReading
        withConsumer:^(NSData *data) {
          [testOutputLineReader consumeData:data];
        }
        error:error]) {
    return NO;
  }

  if (![multiReader
        readWhileBlockRuns:^{
          [task waitUntilExit];
        }
        error:error]) {
    return NO;
  }

  [otestLineReader consumeEndOfFile];
  [testOutputLineReader consumeEndOfFile];
  [otestShimOutputHandle closeFile];
  [testOutputPipe.fileHandleForReading closeFile];

  if (task.terminationStatus != 0 && task.terminationStatus != 1) {
    return [[FBXCTestError describeFormat:@"Subprocess exited with code %d: %@ %@", task.terminationStatus, task.launchPath, task.arguments] failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

- (BOOL)listTestsWithError:(NSError **)error
{
  [self.configuration.reporter didBeginExecutingTestPlan];

  NSString *xctestPath = [self xctestPathForSimulator:nil];
  NSString *installationRoot = [self fbxctestInstallationRoot];
  NSString *otestQueryPath = [installationRoot stringByAppendingPathComponent:@"lib/otest-query-lib-osx.dylib"];
  NSString *otestQueryOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"query-output-pipe"];

  if (mkfifo([otestQueryOutputPath UTF8String], S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestQueryOutputPath] causedBy:posixError] failBool:error];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = xctestPath;
  task.arguments = @[@"-XCTest", @"All", self.configuration.testBundlePath];
  task.environment = [self buildEnvironmentWithEntries:@{
                                                         @"DYLD_INSERT_LIBRARIES": otestQueryPath,
                                                         @"OTEST_QUERY_OUTPUT_FILE": otestQueryOutputPath,
                                                         @"OtestQueryBundlePath": self.configuration.testBundlePath,
                                                         }
                                    targetingSimulator:NO];
  task.standardOutput = [NSFileHandle fileHandleWithStandardError];
  task.standardError = [NSFileHandle fileHandleWithStandardError];
  [task launch];

  NSFileHandle *otestQueryOutputHandle = [NSFileHandle fileHandleForReadingAtPath:otestQueryOutputPath];
  if (otestQueryOutputHandle == nil) {
    return [[FBXCTestError describeFormat:@"Failed to open fifo for reading: %@", otestQueryOutputPath] failBool:error];
  }

  FBMultiFileReader *multiReader = [FBMultiFileReader fileReader];
  NSMutableData *queryOutput = [NSMutableData data];

  if (![multiReader
        addFileHandle:otestQueryOutputHandle
        withConsumer:^(NSData *data) {
          [queryOutput appendData:data];
        }
        error:error]) {
    return NO;
  }

  if (![multiReader
        readWhileBlockRuns:^{
          [task waitUntilExit];
        }
        error:error]) {
    return NO;
  }

  [otestQueryOutputHandle closeFile];

  NSArray<NSString *> *testNames = [NSJSONSerialization JSONObjectWithData:queryOutput options:0 error:error];
  if (testNames == nil) {
    return NO;
  }
  for (NSString *testName in testNames) {
    NSRange slashRange = [testName rangeOfString:@"/"];
    if (slashRange.length == 0) {
      return [[FBXCTestError describeFormat:@"Received unexpected test name from xctool: %@", testName] failBool:error];
    }
    NSString *className = [testName substringToIndex:slashRange.location];
    NSString *methodName = [testName substringFromIndex:slashRange.location + 1];
    [self.configuration.reporter testCaseDidStartForTestClass:className method:methodName];
    [self.configuration.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0];
  }

  if (task.terminationStatus != 0) {
    return [[FBXCTestError describeFormat:@"Subprocess exited with code %d: %@ %@", task.terminationStatus, task.launchPath, task.arguments] failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

- (NSString *)xctestPathForSimulator:(FBSimulator *)simulator
{
  if (simulator == nil) {
    return [FBControlCoreGlobalConfiguration.developerDirectory
            stringByAppendingPathComponent:@"usr/bin/xctest"];
  } else {
    return [FBControlCoreGlobalConfiguration.developerDirectory
            stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"];
  }
}

- (NSString *)fbxctestInstallationRoot
{
  NSString *executablePath = [NSProcessInfo processInfo].arguments[0];
  if (!executablePath.isAbsolutePath) {
    executablePath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingString:executablePath];
  }
  executablePath = [executablePath stringByStandardizingPath];
  return executablePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
}

- (NSDictionary<NSString *, NSString *> *)buildEnvironmentWithEntries:(NSDictionary<NSString *, NSString *> *)entries targetingSimulator:(BOOL)simulator
{
  NSDictionary *parentEnvironment = [NSProcessInfo processInfo].environment;
  NSMutableDictionary *environmentOverrides = [NSMutableDictionary dictionary];
  NSString *xctoolTestEnvPrefix = @"XCTOOL_TEST_ENV_";
  for (NSString *key in parentEnvironment) {
    if ([key hasPrefix:xctoolTestEnvPrefix]) {
      NSString *childKey = [key substringFromIndex:xctoolTestEnvPrefix.length];
      environmentOverrides[childKey] = parentEnvironment[key];
    }
  }
  [environmentOverrides addEntriesFromDictionary:entries];
  NSMutableDictionary *environment = parentEnvironment.mutableCopy;
  for (NSString *key in environmentOverrides) {
    NSString *childKey = key;
    if (simulator) {
      childKey = [@"SIMCTL_CHILD_" stringByAppendingString:childKey];
    }
    environment[childKey] = environmentOverrides[key];
  }
  return environment.copy;
}

@end
