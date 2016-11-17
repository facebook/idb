/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicTestRunner.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestReporter.h"
#import "FBXCTestError.h"
#import "FBXCTestLogger.h"
#import "FBXCTestShimConfiguration.h"

static NSTimeInterval const CrashLogStartDateFuzz = -10;

@interface FBLogicTestRunner ()

@property (nonatomic, strong, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBLogicTestConfiguration *configuration;

@end

@implementation FBLogicTestRunner

+ (instancetype)withSimulator:(nullable FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration];
}

- (instancetype)initWithSimulator:(nullable FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;

  return self;
}

- (BOOL)runTestsWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];

  [self.configuration.reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.configuration.xctestPath;
  NSString *simctlPath = [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"usr/bin/simctl"];
  NSString *otestShimPath = simulator ? self.configuration.shims.iOSSimulatorOtestShimPath : self.configuration.shims.macOtestShimPath;
  NSString *otestShimOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"shim-output-pipe"];
  NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"DYLD_INSERT_LIBRARIES": otestShimPath,
    @"OTEST_SHIM_STDOUT_FILE": otestShimOutputPath,
  }];
  [environment addEntriesFromDictionary:self.configuration.processUnderTestEnvironment];

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
  task.environment = [self.configuration buildEnvironmentWithEntries:environment];
  task.standardOutput = testOutputPipe.fileHandleForWriting;
  task.standardError = testOutputPipe.fileHandleForWriting;
  [task launch];

  [testOutputPipe.fileHandleForWriting closeFile];

  NSFileHandle *otestShimOutputHandle = [NSFileHandle fileHandleForReadingAtPath:otestShimOutputPath];
  if (otestShimOutputHandle == nil) {
    return [[FBXCTestError describeFormat:@"Failed to open fifo for reading: %@", otestShimOutputPath] failBool:error];
  }

  FBMultiFileReader *multiReader = [FBMultiFileReader new];

  FBLineReader *otestLineReader = [FBLineReader lineReaderWithConsumer:^(NSString *line){
    if ([line length] == 0) {
      return;
    }
    NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
    if (event == nil) {
      [self.configuration.logger logFormat:@"Received unexpected output from otest-shim:\n%@", line];
    }
    [self.configuration.reporter handleExternalEvent:event];
  }];
  if (![multiReader addFileHandle:otestShimOutputHandle withConsumer:otestLineReader error:error]) {
    return NO;
  }

  FBLineReader *testOutputLineReader = [FBLineReader lineReaderWithConsumer:^(NSString *line){
    [self.configuration.reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  if (![multiReader addFileHandle:testOutputPipe.fileHandleForReading withConsumer:testOutputLineReader error:error]) {
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
    FBCrashLogInfo *crashLogInfo = [FBLogicTestRunner crashLogsForChildProcessOf:task since:startDate];
    if (crashLogInfo) {
      FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        failBool:error];
    }
    return [[FBXCTestError
      describeFormat:@"Subprocess exited with a crashing code %d but no crash log was found: %@ %@", task.terminationStatus, task.launchPath, task.arguments]
      failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(NSTask *)task since:(NSDate *)sinceDate
{
  NSSet<NSNumber *> *possiblePPIDs = [NSSet setWithArray:@[
    @(task.processIdentifier),
    @(NSProcessInfo.processInfo.processIdentifier),
  ]];

  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
    return [possiblePPIDs containsObject:@(crashLogInfo.parentProcessIdentifier)];
  }];
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^ FBCrashLogInfo * {
    return [[[FBCrashLogInfo
      crashInfoAfterDate:sinceDate]
      filteredArrayUsingPredicate:crashLogInfoPredicate]
      firstObject];
  }];
}

@end
