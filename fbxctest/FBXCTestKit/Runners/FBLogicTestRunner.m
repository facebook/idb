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
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBLogicTestProcess.h"
#import "FBXCTestContext.h"

@interface FBLogicTestRunner ()

@property (nonatomic, strong, readonly) FBLogicTestConfiguration *configuration;
@property (nonatomic, strong, readonly) FBXCTestContext *context;

@end

@interface FBLogicTestRunner_iOS : FBLogicTestRunner

@property (nonatomic, strong, nullable, readonly) FBSimulator *simulator;

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context;

@end

@interface FBLogicTestRunner_macOS : FBLogicTestRunner

@end

@implementation FBLogicTestRunner

#pragma mark Initializers

+ (instancetype)iOSRunnerWithSimulator:(FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  return [[FBLogicTestRunner_iOS alloc] initWithSimulator:simulator configuration:configuration context:context];
}

+ (instancetype)macOSRunnerWithConfiguration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  return [[FBLogicTestRunner_macOS alloc] initWithConfiguration:configuration context:context];
}

- (instancetype)initWithConfiguration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _context = context;

  return self;
}

#pragma mark Public

- (BOOL)executeWithError:(NSError **)error
{
  id<FBXCTestReporter> reporter = self.context.reporter;
  FBXCTestLogger *logger = self.context.logger;

  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *otestShimPath = self.otestShimPath;

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
  FBLogicTestProcess *process = [self testProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutReader:stdOutReader stdErrReader:stdErrReader];
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

- (NSString *)otestShimPath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBLogicTestProcess *)testProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBLogicTestRunner_macOS

#pragma mark Private

- (FBLogicTestProcess *)testProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  return [FBLogicTestProcess
    taskProcessWithLaunchPath:launchPath
    arguments:arguments
    environment:[self.configuration buildEnvironmentWithEntries:environment]
    waitForDebugger:self.configuration.waitForDebugger
    stdOutReader:stdOutReader
    stdErrReader:stdErrReader];
}

- (NSString *)otestShimPath
{
  return self.configuration.shims.macOtestShimPath;
}

@end

@implementation FBLogicTestRunner_iOS

#pragma mark Initializers

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context
{
  self = [super initWithConfiguration:configuration context:context];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Private

- (FBLogicTestProcess *)testProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader
{
  return [FBLogicTestProcess
    simulatorSpawnProcess:self.simulator
    launchPath:launchPath
    arguments:arguments
    environment:[self.configuration buildEnvironmentWithEntries:environment]
    waitForDebugger:self.configuration.waitForDebugger
    stdOutReader:stdOutReader
    stdErrReader:stdErrReader];
}

- (NSString *)otestShimPath
{
  return self.configuration.shims.iOSSimulatorOtestShimPath;
}

@end
