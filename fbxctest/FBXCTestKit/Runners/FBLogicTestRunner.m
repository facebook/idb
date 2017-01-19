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
#import "FBXCTestDestination.h"

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

  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *simctlPath = [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"usr/bin/simctl"];
  NSString *otestShimPath = simulator ? self.configuration.shims.iOSSimulatorOtestShimPath : self.configuration.shims.macOtestShimPath;

  // The fifo is used by the shim to report events from within the xctest framework.
  NSString *otestShimOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"shim-output-pipe"];
  if (mkfifo(otestShimOutputPath.UTF8String, S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestShimOutputPath] causedBy:posixError] failBool:error];
  }

  // The environment requires the shim path and otest-shim path.
  NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"DYLD_INSERT_LIBRARIES": otestShimPath,
    @"OTEST_SHIM_STDOUT_FILE": otestShimOutputPath,
  }];
  [environment addEntriesFromDictionary:self.configuration.processUnderTestEnvironment];

  // Get the Launch Path and Arguments for the xctest process.
  NSString *testSpecifier = self.configuration.testFilter ?: @"All";
  NSString *launchPath = simulator ? simctlPath : xctestPath;
  NSArray<NSString *> *arguments = simulator
    ? @[@"--set", simulator.deviceSetPath, @"spawn", simulator.udid, xctestPath, @"-XCTest", testSpecifier, self.configuration.testBundlePath]
    : @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];

  // Consumes the test output. Separate Readers are used as consuming an EOF will invalidate the reader.
  dispatch_queue_t queue = dispatch_get_main_queue();
  id<FBFileDataConsumer> stdOutReader = [FBLineFileDataConsumer lineReaderWithQueue:queue consumer:^(NSString *line){
    [self.configuration.reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  id<FBFileDataConsumer> stdErrReader = [FBLineFileDataConsumer lineReaderWithQueue:queue consumer:^(NSString *line){
    [self.configuration.reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  // Consumes the shim output.
  id<FBFileDataConsumer> otestShimLineReader = [FBLineFileDataConsumer lineReaderWithQueue:queue consumer:^(NSString *line){
    if ([line length] == 0) {
      return;
    }
    NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
    if (event == nil) {
      [self.configuration.logger logFormat:@"Received unexpected output from otest-shim:\n%@", line];
    }
    [self.configuration.reporter handleExternalEvent:event];
  }];

  // Construct and launch the task.
  FBTask *task = [[[[[[[[FBTaskBuilder
    withLaunchPath:launchPath]
    withArguments:arguments]
    withEnvironment:[self.configuration buildEnvironmentWithEntries:environment]]
    withStdOutConsumer:stdOutReader]
    withStdErrConsumer:stdErrReader]
    withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
    build]
    startAsynchronously];

  // Create a reader of the otest-shim path and start reading it.
  NSError *innerError = nil;
  FBFileReader *otestShimReader = [FBFileReader readerWithFilePath:otestShimOutputPath consumer:otestShimLineReader error:&innerError];
  if (!otestShimReader) {
    [task terminate];
    return [[[FBXCTestError
      describeFormat:@"Failed to open fifo for reading: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }
  if (![otestShimReader startReadingWithError:&innerError]) {
    [task terminate];
    return [[[FBXCTestError
      describeFormat:@"Failed to start reading fifo: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }

  // Wait for the xctest process to finish.
  NSError *timeoutError = nil;
  BOOL waitSuccessful = [task waitForCompletionWithTimeout:self.configuration.testTimeout error:&timeoutError];

  // Fail if we can't close.
  if (![otestShimReader stopReadingWithError:&innerError]) {
    [task terminate];
    return [[[FBXCTestError
      describeFormat:@"Failed to stop reading fifo: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }

  // If the xctest process has stalled, we should sample it (if possible), then terminate it.
  if (!waitSuccessful) {
    pid_t xctestProcessIdentifier = simulator
      ? [FBLogicTestRunner xctestProcessIdentiferForSimctlParent:task.processIdentifier fetcher:simulator.processFetcher.processFetcher]
      : task.processIdentifier;

    NSString *sample = [FBLogicTestRunner sampleStalledProcess:xctestProcessIdentifier];
    [task terminate];
    return [[[FBXCTestError
      describeFormat:@"The xctest process stalled: %@", sample]
      causedBy:timeoutError]
      failBool:error];
  }

  // Fail on error event.
  if (task.error) {
    FBCrashLogInfo *crashLogInfo = [FBLogicTestRunner crashLogsForChildProcessOf:task.processIdentifier since:startDate];
    if (crashLogInfo) {
      FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        causedBy:task.error]
        failBool:error];
    }
    return [[[FBXCTestError
      describeFormat:@"xctest process exited abnormally %@", task.error.localizedDescription]
      causedBy:task.error]
      failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

+ (pid_t)xctestProcessIdentiferForSimctlParent:(pid_t)simctlProcessIdentifier fetcher:(FBProcessFetcher *)fetcher
{
  pid_t xctestProcessIdentifier = [fetcher subprocessOf:simctlProcessIdentifier withName:@"xctest"];
  if (xctestProcessIdentifier < 1) {
    return simctlProcessIdentifier;
  }
  return xctestProcessIdentifier;
}

+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  NSSet<NSNumber *> *possiblePPIDs = [NSSet setWithArray:@[
    @(processIdentifier),
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

+ (nullable NSString *)sampleStalledProcess:(pid_t)processIdentifier
{
  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    build]
    startSynchronouslyWithTimeout:5]
    stdOut];
}

@end
