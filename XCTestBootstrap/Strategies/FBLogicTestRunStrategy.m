/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLogicTestRunStrategy.h"
#import "FBLogicXCTestReporter.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

static NSTimeInterval EndOfFileFromStopReadingTimeout = 5;

@interface FBLogicTestRunOutputs : NSObject

@property (nonatomic, strong, readonly) id<FBDataConsumer, FBDataConsumerLifecycle> stdOutConsumer;
@property (nonatomic, strong, readonly) id<FBDataConsumer, FBDataConsumerLifecycle> stdErrConsumer;
@property (nonatomic, strong, readonly) id<FBDataConsumer, FBDataConsumerLifecycle> shimConsumer;
@property (nonatomic, strong, readonly) id<FBProcessFileOutput> shimOutput;

@end

@implementation FBLogicTestRunOutputs

- (instancetype)initWithStdOutConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)stdErrConsumer shimConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)shimConsumer shimOutput:(id<FBProcessFileOutput>)shimOutput
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stdOutConsumer = stdOutConsumer;
  _stdErrConsumer = stdErrConsumer;
  _shimConsumer = shimConsumer;
  _shimOutput = shimOutput;

  return self;
}

@end

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
    onQueue:self.executor.workQueue fmap:^(FBLogicTestRunOutputs *outputs) {
      return [self testFutureWithOutputs:outputs uuid:uuid];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)testFutureWithOutputs:(FBLogicTestRunOutputs *)outputs uuid:(NSUUID *)uuid
{
  [self.logger logFormat:@"Starting Logic Test execution of %@", self.configuration];
  id<FBLogicXCTestReporter> reporter = self.reporter;
  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.executor.xctestPath;
  NSString *shimPath = self.executor.shimPath;

  // The environment the bundle path to the xctest target and where to redirect stdout to.
  NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:@{
    @"DYLD_INSERT_LIBRARIES": shimPath,
    @"TEST_SHIM_STDOUT_PATH": outputs.shimOutput.filePath,
    @"TEST_SHIM_BUNDLE_PATH": self.configuration.testBundlePath,
  }];
  [environment addEntriesFromDictionary:self.configuration.processUnderTestEnvironment];

  // Get the Launch Path and Arguments for the xctest process.
  NSString *testSpecifier = self.configuration.testFilter ?: @"All";
  NSString *launchPath = xctestPath;
  NSArray<NSString *> *arguments = @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];

  // Construct and start the process
  return [[self
    startTestProcessWithLaunchPath:launchPath arguments:arguments environment:environment outputs:outputs]
    onQueue:self.executor.workQueue fmap:^(FBFuture<NSNumber *> *exitCode) {
      return [self completeLaunchedProcess:exitCode outputs:outputs];
    }];
}

- (FBFuture<NSNull *> *)completeLaunchedProcess:(FBFuture<NSNumber *> *)exitCode outputs:(FBLogicTestRunOutputs *)outputs
{
  id<FBControlCoreLogger> logger = self.logger;
  id<FBLogicXCTestReporter> reporter = self.reporter;
  dispatch_queue_t queue = self.executor.workQueue;

  [logger logFormat:@"Starting to read shim output from location %@", outputs.shimOutput.filePath];

  return [[[[outputs.shimOutput
    startReading]
    onQueue:queue fmap:^(id _) {
      [logger logFormat:@"Shim output at %@ has been opened for reading, waiting for xctest process to exit", outputs.shimOutput.filePath];
      return [self waitForSuccessfulCompletion:exitCode closingOutputs:outputs];
    }]
    onQueue:queue map:^(id _) {
      [logger log:@"Normal exit of xctest process"];
      [reporter didFinishExecutingTestPlan];
      return NSNull.null;
    }]
    onQueue:queue handleError:^(NSError *error) {
      [logger logFormat:@"Abnormal exit of xctest process %@", error];
      [reporter didCrashDuringTest:error];
      return [FBFuture futureWithError:error];
    }];
}

- (FBFuture<NSNumber *> *)waitForSuccessfulCompletion:(FBFuture<NSNumber *> *)exitCode closingOutputs:(FBLogicTestRunOutputs *)outputs
{
  id<FBControlCoreLogger> logger = self.logger;
  dispatch_queue_t queue = self.executor.workQueue;
  return [[exitCode
    onQueue:queue chain:^(id _) {
      // Since there's no guarantee that the xctest process has closed the writing end of the fifo, we can't rely on getting and end-of-file naturally
      // This means that we have to stop reading manually instead.
      // However, we want to ensure that we've read all the way to the end of the file so that no test results are missing, since the reading is asynchronous.
      // The stopReading will cause the end-of-file to be sent to the consumer, this is a guarantee that the FBFileReader API makes.
      // To prevent this from hanging indefinately, we also wrap this in a reasonable timeout so we have a better message in the worst-case scenario.
      // This teardown is performed unconditionally once the exit code future has resolved so that we clean up from error states.
      [logger log:@"xctest process terminated, Tearing down IO."];
      return [[[FBFuture
        futureWithFutures:@[
          [outputs.shimOutput stopReading],
          [outputs.shimConsumer finishedConsuming],
        ]]
        timeout:EndOfFileFromStopReadingTimeout waitingFor:@"receive and end-of-file after fifo has been stopped, as the process has already exited with code %@", exitCode]
        chainReplace:exitCode];
    }]
    onQueue:queue fmap:^ FBFuture<NSNull *> * (NSNumber *exitCodeNumber) {
      [logger logFormat:@"xctest process terminated, exited with %@, checking status code", exitCodeNumber];
      int exitCodeValue = exitCodeNumber.intValue;
      NSString *descriptionOfExit = [FBXCTestProcess describeFailingExitCode:exitCodeValue];
      if (descriptionOfExit) {
        return [[FBControlCoreError
          describeFormat:@"xctest process exited in failure (%d): %@", exitCodeValue, descriptionOfExit]
          failFuture];
      }
      return [FBFuture futureWithResult:exitCodeNumber];
    }];
}

+ (FBFuture<NSNull *> *)fromQueue:(dispatch_queue_t)queue waitForDebuggerToBeAttached:(BOOL)waitFor forProcessIdentifier:(pid_t)processIdentifier reporter:(id<FBLogicXCTestReporter>)reporter
{
  if (!waitFor) {
    return FBFuture.empty;
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

      return FBFuture.empty;
    }]
    onQueue:queue map:^(id _) {
      [reporter debuggerAttached];
      return NSNull.null;
    }];
}

- (FBFuture<FBLogicTestRunOutputs *> *)buildOutputsForUUID:(NSUUID *)udid
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

  id<FBDataConsumer> shimReportingConsumer = [FBBlockDataConsumer asynchronousLineConsumerWithQueue:queue dataConsumer:^(NSData *line) {
    [reporter handleEventJSONData:line];
  }];
  [shimConsumers addObject:shimReportingConsumer];

  id<FBDataConsumer> stdOutReportingConsumer = [FBBlockDataConsumer asynchronousLineConsumerWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  [stdOutConsumers addObject:stdOutReportingConsumer];

  id<FBDataConsumer> stdErrReportingConsumer = [FBBlockDataConsumer asynchronousLineConsumerWithQueue:queue consumer:^(NSString *line){
    [reporter testHadOutput:[line stringByAppendingString:@"\n"]];
  }];
  [stdErrConsumers addObject:stdErrReportingConsumer];

  if (mirrorToLogger) {
    [shimConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
    [stdErrConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
    [stdErrConsumers addObject:[FBLoggingDataConsumer consumerWithLogger:logger]];
  }

  id<FBDataConsumer, FBDataConsumerLifecycle> stdOutConsumer = [FBCompositeDataConsumer consumerWithConsumers:stdOutConsumers];
  id<FBDataConsumer, FBDataConsumerLifecycle> stdErrConsumer = [FBCompositeDataConsumer consumerWithConsumers:stdErrConsumers];
  id<FBDataConsumer, FBDataConsumerLifecycle> shimConsumer = [FBCompositeDataConsumer consumerWithConsumers:shimConsumers];

  FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *stdOutFuture = [FBFuture futureWithResult:stdOutConsumer];
  FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *stdErrFuture = [FBFuture futureWithResult:stdErrConsumer];
  FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *shimFuture = [FBFuture futureWithResult:shimConsumer];
  if (mirrorToFiles) {
    stdOutFuture = [mirrorLogger logConsumptionToFile:stdOutConsumer outputKind:@"out" udid:udid logger:logger];
    stdErrFuture = [mirrorLogger logConsumptionToFile:stdErrConsumer outputKind:@"err" udid:udid logger:logger];
    shimFuture = [mirrorLogger logConsumptionToFile:shimConsumer outputKind:@"shim" udid:udid logger:logger];
  }
  return [[FBFuture
    futureWithFutures:@[
      stdOutFuture, stdErrFuture, shimFuture
    ]]
    onQueue:self.executor.workQueue fmap:^(NSArray<id<FBDataConsumer, FBDataConsumerLifecycle>> *outputs) {
      return [[[FBProcessOutput
        outputForDataConsumer:outputs[2]]
        providedThroughFile]
        onQueue:self.executor.workQueue map:^(id<FBProcessFileOutput> shimOutput) {
          return [[FBLogicTestRunOutputs alloc] initWithStdOutConsumer:outputs[0] stdErrConsumer:outputs[1] shimConsumer:outputs[2] shimOutput:shimOutput];
        }];
    }];
}

- (FBFuture<FBFuture<NSNumber *> *> *)startTestProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment outputs:(FBLogicTestRunOutputs *)outputs
{
  dispatch_queue_t queue = self.executor.workQueue;
  id<FBControlCoreLogger> logger = self.logger;
  id<FBLogicXCTestReporter> reporter = self.reporter;
  NSTimeInterval timeout = self.configuration.testTimeout;

  [logger logFormat:
    @"Launching xctest process with arguments %@, environment %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[@[launchPath] arrayByAddingObjectsFromArray:arguments]],
    [FBCollectionInformation oneLineDescriptionFromDictionary:environment]
  ];
  return [[self.executor
    startProcessWithLaunchPath:launchPath arguments:arguments environment:environment stdOutConsumer:outputs.stdOutConsumer stdErrConsumer:outputs.stdErrConsumer]
    onQueue:queue map:^ FBFuture<NSNumber *> * (id<FBLaunchedProcess> process) {
      return [[FBLogicTestRunStrategy
        fromQueue:queue waitForDebuggerToBeAttached:self.configuration.waitForDebugger forProcessIdentifier:process.processIdentifier reporter:reporter]
        onQueue:queue fmap:^(id _) {
          return [FBXCTestProcess ensureProcess:process completesWithin:timeout withCrashLogDetection:YES queue:queue logger:logger];
        }];
    }];
}

@end
