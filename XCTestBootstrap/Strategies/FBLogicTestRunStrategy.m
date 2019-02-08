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

static NSTimeInterval EndOfFileFromStopReadingTimeout = 5;

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
  return [self testFuture];
}

- (FBFuture<NSNull *> *)testFuture
{
  NSUUID *uuid = NSUUID.UUID;

  return [[self
    buildOutputsForUUID:uuid]
    onQueue:self.executor.workQueue fmap:^(NSArray<id<FBDataConsumer, FBDataConsumerLifecycle>> *outputs) {
      id<FBDataConsumer, FBDataConsumerLifecycle> stdOut = outputs[0];
      id<FBDataConsumer, FBDataConsumerLifecycle> stdErr = outputs[1];
      id<FBDataConsumer, FBDataConsumerLifecycle> shim = outputs[2];
      return [self testFutureWithStdOutConsumer:stdOut stdErrConsumer:stdErr shimConsumer:shim uuid:uuid];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)testFutureWithStdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer shimConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)shimConsumer uuid:(NSUUID *)uuid
{
  return [[[FBProcessOutput
    outputForDataConsumer:shimConsumer]
    providedThroughFile]
    onQueue:self.executor.workQueue fmap:^(id<FBProcessFileOutput> shimOutput) {
      return [self
        testFutureWithShimOutput:shimOutput
        stdOutConsumer:stdOutConsumer
        stdErrConsumer:stdErrConsumer
        shimConsumer:shimConsumer
        uuid:uuid];
    }];
}

- (FBFuture<NSNull *> *)testFutureWithShimOutput:(id<FBProcessFileOutput>)shimOutput stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer shimConsumer:(id<FBDataConsumerLifecycle>)shimConsumer uuid:(NSUUID *)uuid
{
  [self.logger logFormat:@"Starting Logic Test execution of %@", [FBCollectionInformation oneLineJSONDescription:self.configuration]];
  id<FBLogicXCTestReporter> reporter = self.reporter;
  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.executor.xctestPath;
  NSString *shimPath = self.executor.shimPath;

  // The environment requires the shim path and otest-shim path.
  NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"DYLD_INSERT_LIBRARIES": shimPath,
    @"OTEST_SHIM_STDOUT_FILE": shimOutput.filePath,
    @"TEST_SHIM_BUNDLE_PATH": self.configuration.testBundlePath,
    @"FB_TEST_TIMEOUT": @(self.configuration.testTimeout).stringValue,
  }];
  [environment addEntriesFromDictionary:self.configuration.processUnderTestEnvironment];

  // Get the Launch Path and Arguments for the xctest process.
  NSString *testSpecifier = self.configuration.testFilter ?: @"All";
  NSString *launchPath = xctestPath;
  NSArray<NSString *> *arguments = @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];

  // Construct and start the process
  return [[self
    startTestProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutConsumer:stdOutConsumer stdErrConsumer:stdErrConsumer]
    onQueue:self.executor.workQueue fmap:^(id<FBLaunchedProcess> process) {
      return [self
        completeLaunchedProcess:process
        shimOutput:shimOutput
        shimConsumer:shimConsumer];
    }];
}

- (FBFuture<NSNull *> *)completeLaunchedProcess:(id<FBLaunchedProcess>)process shimOutput:(id<FBProcessFileOutput>)shimOutput shimConsumer:(id<FBDataConsumerLifecycle>)shimConsumer
{
  id<FBLogicXCTestReporter> reporter = self.reporter;
  dispatch_queue_t queue = self.executor.workQueue;

  return [[[[[FBLogicTestRunStrategy
    fromQueue:queue waitForDebuggerToBeAttached:self.configuration.waitForDebugger forProcessIdentifier:process.processIdentifier reporter:reporter]
    onQueue:queue fmap:^(id _) {
      return [shimOutput startReading];
    }]
    onQueue:queue fmap:^(FBFileReader *reader) {
      return [FBLogicTestRunStrategy onQueue:queue waitForExit:process closingOutput:shimOutput consumer:shimConsumer];
    }]
    onQueue:queue handleError:^(NSError *error) {
      [self.logger logFormat:@"Abnormal exit of xctest process %@", error];
      [self.reporter didCrashDuringTest:error];
      return [FBFuture futureWithError:error];
    }]
    onQueue:queue map:^(id _) {
      [self.logger log:@"Normal exit of xctest process"];
      [reporter didFinishExecutingTestPlan];
      return NSNull.null;
    }];
}

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForExit:(id<FBLaunchedProcess>)process closingOutput:(id<FBProcessFileOutput>)output consumer:(id<FBDataConsumerLifecycle>)consumer
{
  return [process.exitCode
    onQueue:queue fmap:^(NSNumber *exitCode) {
      // Since there's no guarantee that the xctest process has closed the writing end of the fifo, we can't rely on getting and end-of-file naturally
      // This means that we have to stop reading manually instead.
      // However, we want to ensure that we've read all the way to the end of the file so that no test results are missing, since the reading is asynchronous.
      // The stopReading will cause the end-of-file to be sent to the consumer, this is a guarantee that the FBFileReader API makes.
      // To prevent this from hanging indefinately, we also wrap this in a reasonable timeout so we have a better message in the worst-case scenario.
      return [[FBFuture
        futureWithFutures:@[
          [output stopReading],
          [consumer eofHasBeenReceived],
        ]]
        timeout:EndOfFileFromStopReadingTimeout waitingFor:@"recieve and end-of-file after fifo has been stopped, as the process has already exited with code %@", exitCode];
    }];
}

+ (FBFuture<NSNull *> *)fromQueue:(dispatch_queue_t)queue waitForDebuggerToBeAttached:(BOOL)waitFor forProcessIdentifier:(pid_t)processIdentifier reporter:(id<FBLogicXCTestReporter>)reporter
{
  if (!waitFor) {
    return [FBFuture futureWithResult:NSNull.null];
  }

  // Report from the current queue, but wait in a special queue.
  dispatch_queue_t waitQueue = dispatch_queue_create("com.facebook.xctestbootstrap.debugger_wait", DISPATCH_QUEUE_SERIAL);
  [reporter processWaitingForDebuggerWithProcessIdentifier:processIdentifier];
  return [[FBFuture
    onQueue:waitQueue resolve:^{
      // If wait_for_debugger is passed, the child process receives SIGSTOP after immediately launch.
      // We wait until it receives SIGCONT from an attached debugger.
      waitid(P_PID, (id_t)processIdentifier, NULL, WCONTINUED);
      [reporter debuggerAttached];

      return [FBFuture futureWithResult:NSNull.null];
    }]
    onQueue:queue map:^(id _) {
      [reporter debuggerAttached];
      return NSNull.null;
    }];
}

- (FBFuture<NSArray<id<FBDataConsumerLifecycle>> *> *)buildOutputsForUUID:(NSUUID *)udid
{
  id<FBLogicXCTestReporter> reporter = self.reporter;
  id<FBControlCoreLogger> logger = self.logger;
  dispatch_queue_t queue = self.executor.workQueue;
  FBXCTestLogger *mirrorLogger = [FBXCTestLogger defaultLoggerInDefaultDirectory];
  BOOL mirrorToLogger = (self.configuration.mirroring & FBLogicTestMirrorLogger) != 0;
  BOOL mirrorToFiles = (self.configuration.mirroring & FBLogicTestMirrorFileLogs) != 0;

  NSMutableArray<id<FBDataConsumer>> *shimConsumers = [NSMutableArray array];
  NSMutableArray<id<FBDataConsumer>> *stdOutConsumers = [NSMutableArray array];
  NSMutableArray<id<FBDataConsumer>> *stdErrConsumers = [NSMutableArray array];

  id<FBDataConsumer> shimReportingConsumer = [FBLineDataConsumer asynchronousReaderWithQueue:queue dataConsumer:^(NSData *line) {
    [reporter handleEventJSONData:line];
  }];
  [shimConsumers addObject:shimReportingConsumer];

  id<FBDataConsumer> stdOutReportingConsumer = [FBLineDataConsumer asynchronousReaderWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  [stdOutConsumers addObject:stdOutReportingConsumer];

  id<FBDataConsumer> stdErrReportingConsumer = [FBLineDataConsumer asynchronousReaderWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  [stdErrConsumers addObject:stdErrReportingConsumer];

  if (mirrorToLogger) {
    [shimConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
    [stdErrConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
    [stdErrConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
  }

  id<FBDataConsumer> stdOutConsumer = [FBCompositeDataConsumer consumerWithConsumers:stdOutConsumers];
  id<FBDataConsumer> stdErrConsumer = [FBCompositeDataConsumer consumerWithConsumers:stdErrConsumers];
  id<FBDataConsumer> shimConsumer = [FBCompositeDataConsumer consumerWithConsumers:shimConsumers];

  if (!mirrorToFiles) {
    return [FBFuture futureWithResult:@[stdOutConsumer, stdErrConsumer, shimConsumer]];
  }

  return [FBFuture
    futureWithFutures:@[
      [mirrorLogger logConsumptionToFile:stdOutConsumer outputKind:@"out" udid:udid logger:logger],
      [mirrorLogger logConsumptionToFile:stdErrConsumer outputKind:@"err" udid:udid logger:logger],
      [mirrorLogger logConsumptionToFile:shimConsumer outputKind:@"shim" udid:udid logger:logger],
    ]];
}

- (FBFuture<id<FBLaunchedProcess>> *)startTestProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer
{
  [self.logger logFormat:
    @"Launching xctest process with arguments %@, environment %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[@[launchPath] arrayByAddingObjectsFromArray:arguments]],
    [FBCollectionInformation oneLineDescriptionFromDictionary:environment]
  ];
  return [FBXCTestProcess
    startWithLaunchPath:launchPath
    arguments:arguments
    environment:[self.configuration buildEnvironmentWithEntries:environment]
    waitForDebugger:self.configuration.waitForDebugger
    stdOutConsumer:stdOutConsumer
    stdErrConsumer:stdErrConsumer
    executor:self.executor
    timeout:self.configuration.testTimeout
    logger:self.logger];
}

@end
