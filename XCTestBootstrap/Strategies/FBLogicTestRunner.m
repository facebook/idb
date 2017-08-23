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
#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBLogicTestRunner ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;
@property (nonatomic, strong, readonly) FBLogicTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBLogicTestRunner

#pragma mark Initializers

+ (instancetype)runnerWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [[FBLogicTestRunner alloc] initWithExecutor:executor configuration:configuration reporter:reporter logger:logger];
}

- (instancetype)initWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
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

- (BOOL)executeWithError:(NSError **)error
{
  id<FBXCTestReporter> reporter = self.reporter;
  FBXCTestLogger *logger = self.logger;

  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *shimPath = self.executor.shimPath;

  // The fifo is used by the shim to report events from within the xctest framework.
  NSString *otestShimOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"shim-output-pipe"];
  if (mkfifo(otestShimOutputPath.UTF8String, S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestShimOutputPath] causedBy:posixError] failBool:error];
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
  dispatch_queue_t queue = dispatch_get_main_queue();


  id<FBFileConsumer> stdOutReader = [FBLineFileConsumer asynchronousReaderWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  stdOutReader = [logger logConsumptionToFile:stdOutReader outputKind:@"out" udid:uuid];
  id<FBFileConsumer> stdErrReader = [FBLineFileConsumer asynchronousReaderWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  stdErrReader = [logger logConsumptionToFile:stdErrReader outputKind:@"err" udid:uuid];
  // Consumes the shim output.
  id<FBFileConsumer> otestShimLineReader = [FBLineFileConsumer asynchronousReaderWithQueue:queue consumer:^(NSString *line){
    [reporter handleExternalEvent:line];
  }];
  otestShimLineReader = [logger logConsumptionToFile:otestShimLineReader outputKind:@"shim" udid:uuid];

  // Construct and start the process
  FBXCTestProcess *process = [self testProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutReader:stdOutReader stdErrReader:stdErrReader];
  pid_t pid = [process startWithError:error];
  if (!pid) {
    return NO;
  }

  if (self.configuration.waitForDebugger) {
    [reporter processWaitingForDebuggerWithProcessIdentifier:pid];
    // If wait_for_debugger is passed, the child process receives SIGSTOP after immediately launch.
    // We wait until it receives SIGCONT from an attached debugger.
    waitid(P_PID, (id_t)pid, NULL, WCONTINUED);
    [reporter debuggerAttached];
  }

  // Create a reader of the otest-shim path and start reading it.
  NSError *innerError = nil;
  FBFileReader *otestShimReader = [FBFileReader readerWithFilePath:otestShimOutputPath consumer:otestShimLineReader error:&innerError];
  if (!otestShimReader) {
    [process terminate];
    return [[[FBXCTestError
      describeFormat:@"Failed to open fifo for reading: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }
  if (![otestShimReader startReadingWithError:&innerError]) {
    [process terminate];
    return [[[FBXCTestError
      describeFormat:@"Failed to start reading fifo: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }

  // Wait for the test process to finish.
  if (![process waitForCompletionWithTimeout:self.configuration.testTimeout error:error]) {
    return NO;
  }

  // Fail if we can't close.
  if (![otestShimReader stopReadingWithError:&innerError]) {
    return [[[FBXCTestError
      describeFormat:@"Failed to stop reading fifo: %@", otestShimOutputPath]
      causedBy:innerError]
      failBool:error];
  }

  [reporter didFinishExecutingTestPlan];

  return YES;
}

#pragma mark Private

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
