/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicTestRunStrategy.h"
#import "FBLogicXCTestReporter.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBLogicTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;
@property (nonatomic, strong, readonly) FBLogicTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBLogicXCTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBLogicTestRunStrategy

#pragma mark Initializers

+ (instancetype)strategyWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBLogicXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [[FBLogicTestRunStrategy alloc] initWithExecutor:executor configuration:configuration reporter:reporter logger:logger];
}

- (instancetype)initWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBLogicXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _executor = executor;
  _configuration = configuration;
  _reporter = reporter;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)execute
{
  NSTimeInterval timeout = self.configuration.testTimeout + 5;
  return [[self testFuture] timedOutIn:timeout];
}

- (FBFuture<NSNull *> *)testFuture
{
  id<FBLogicXCTestReporter> reporter = self.reporter;
  BOOL mirrorToFiles = (self.configuration.mirroring & FBLogicTestMirrorFileLogs) != 0;
  BOOL mirrorToLogger = (self.configuration.mirroring & FBLogicTestMirrorLogger) != 0;
  id<FBControlCoreLogger> logger = self.logger;
  FBXCTestLogger *mirrorLogger = [FBXCTestLogger defaultLoggerInDefaultDirectory];

  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *shimPath = self.executor.shimPath;

  // The fifo is used by the shim to report events from within the xctest framework.
  NSString *otestShimOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"shim-output-pipe"];
  if (mkfifo(otestShimOutputPath.UTF8String, S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError
      describeFormat:@"Failed to create a named pipe %@", otestShimOutputPath]
      causedBy:posixError]
      failFuture];
  }

  // The environment requires the shim path and otest-shim path.
  NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"DYLD_INSERT_LIBRARIES": shimPath,
    @"OTEST_SHIM_STDOUT_FILE": otestShimOutputPath,
    @"TEST_SHIM_BUNDLE_PATH": self.configuration.testBundlePath,
    @"FB_TEST_TIMEOUT": @(self.configuration.testTimeout).stringValue,
  }];
  [environment addEntriesFromDictionary:self.configuration.processUnderTestEnvironment];

  // Get the Launch Path and Arguments for the xctest process.
  NSString *testSpecifier = self.configuration.testFilter ?: @"All";
  NSString *launchPath = xctestPath;
  NSArray<NSString *> *arguments = @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];

  // Consumes the test output. Separate Readers are used as consuming an EOF will invalidate the reader.
  NSUUID *uuid = [NSUUID UUID];

  // Setup the stdout reader.
  id<FBFileConsumer> stdOutReader = [FBLineFileConsumer asynchronousReaderWithQueue:self.executor.workQueue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
    if (mirrorToLogger) {
      [mirrorLogger logFormat:@"[Test Output] %@", line];
    }
  }];
  if (mirrorToFiles) {
    NSString *mirrorPath = nil;
    stdOutReader = [mirrorLogger logConsumptionToFile:stdOutReader outputKind:@"out" udid:uuid filePathOut:&mirrorPath];
    [logger logFormat:@"Mirroring xctest stdout to %@", mirrorPath];
  }

  // Setup the stderr reader.
  id<FBFileConsumer> stdErrReader = [FBLineFileConsumer asynchronousReaderWithQueue:self.executor.workQueue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
    if (mirrorToLogger) {
      [mirrorLogger logFormat:@"[Test Output(err)] %@", line];
    }
  }];
  if (mirrorToFiles) {
    NSString *mirrorPath = nil;
    stdErrReader = [mirrorLogger logConsumptionToFile:stdErrReader outputKind:@"err" udid:uuid filePathOut:&mirrorPath];
    [logger logFormat:@"Mirroring xctest stderr to %@", mirrorPath];
  }

  // Setup the reader of the shim
  FBLineFileConsumer *otestShimLineReader = [FBLineFileConsumer asynchronousReaderWithQueue:self.executor.workQueue dataConsumer:^(NSData *line) {
    [reporter handleEventJSONData:line];
    if (mirrorToLogger) {
      NSString *stringLine = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
      [mirrorLogger logFormat:@"[Shim StdOut] %@", stringLine];
    }
  }];

  id<FBFileConsumer> otestShimConsumer = otestShimLineReader;
  if (mirrorToFiles) {
    // Mirror the output
    NSString *mirrorPath = nil;
    otestShimConsumer = [mirrorLogger logConsumptionToFile:otestShimLineReader outputKind:@"shim" udid:uuid filePathOut:&mirrorPath];
    [logger logFormat:@"Mirroring shim-fifo output to %@", mirrorPath];
  }

  // Construct and start the process
  return [[[self
    testProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutReader:stdOutReader stdErrReader:stdErrReader]
    startWithTimeout:self.configuration.testTimeout]
    onQueue:self.executor.workQueue fmap:^(FBLaunchedProcess *processInfo) {
      return [self
        completeLaunchedProcess:processInfo
        otestShimOutputPath:otestShimOutputPath
        otestShimConsumer:otestShimConsumer
        otestShimLineReader:otestShimLineReader];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)completeLaunchedProcess:(FBLaunchedProcess *)processInfo otestShimOutputPath:(NSString *)otestShimOutputPath otestShimConsumer:(id<FBFileConsumer>)otestShimConsumer otestShimLineReader:(FBLineFileConsumer *)otestShimLineReader
{
  id<FBLogicXCTestReporter> reporter = self.reporter;
  if (self.configuration.waitForDebugger) {
    [reporter processWaitingForDebuggerWithProcessIdentifier:processInfo.processIdentifier];
    // If wait_for_debugger is passed, the child process receives SIGSTOP after immediately launch.
    // We wait until it receives SIGCONT from an attached debugger.
    waitid(P_PID, (id_t)processInfo.processIdentifier, NULL, WCONTINUED);
    [reporter debuggerAttached];
  }

  // Create a reader of the otest-shim path and start reading it.
  NSError *error = nil;
  FBFileReader *otestShimReader = [FBFileReader readerWithFilePath:otestShimOutputPath consumer:otestShimConsumer error:&error];
  if (!otestShimReader) {
    [processInfo.exitCode cancel];
    return [[[FBXCTestError
      describeFormat:@"Failed to open fifo for reading: %@", otestShimOutputPath]
      causedBy:error]
      failFuture];
  }

  return [[[[otestShimReader
    startReading]
    fmapReplace:processInfo.exitCode]
    onQueue:self.executor.workQueue fmap:^(id _) {
      // Close and wait
      return [FBFuture futureWithFutures:@[
        [otestShimReader stopReading],
        [otestShimLineReader eofHasBeenReceived],
      ]];
    }]
    onQueue:self.executor.workQueue map:^(id _) {
      [reporter didFinishExecutingTestPlan];
      return NSNull.null;
    }];
}

- (FBXCTestProcess *)testProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  return [FBXCTestProcess
    processWithLaunchPath:launchPath
    arguments:arguments
    environment:[self.configuration buildEnvironmentWithEntries:environment]
    waitForDebugger:self.configuration.waitForDebugger
    stdOutReader:stdOutReader
    stdErrReader:stdErrReader
    executor:self.executor];
}

@end
