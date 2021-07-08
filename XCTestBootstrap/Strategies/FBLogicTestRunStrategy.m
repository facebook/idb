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
@property (nonatomic, strong, readonly) id<FBConsumableBuffer> stdErrBuffer;
@property (nonatomic, strong, readonly) id<FBDataConsumer, FBDataConsumerLifecycle> shimConsumer;
@property (nonatomic, strong, readonly) id<FBProcessFileOutput> shimOutput;

@end

@implementation FBLogicTestRunOutputs

- (instancetype)initWithStdOutConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)stdErrConsumer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer shimConsumer:(id<FBDataConsumer, FBDataConsumerLifecycle>)shimConsumer shimOutput:(id<FBProcessFileOutput>)shimOutput
{
  self = [super init];
  if (!self) {
      return nil;
  }

  _stdOutConsumer = stdOutConsumer;
  _stdErrConsumer = stdErrConsumer;
  _stdErrBuffer = stdErrBuffer;
  _shimConsumer = shimConsumer;
  _shimOutput = shimOutput;

  return self;
}

@end

@interface FBLogicTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands> target;
@property (nonatomic, strong, readonly) FBLogicTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBLogicXCTestReporter> reporter;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBLogicTestRunStrategy

#pragma mark Initializers

- (instancetype)initWithTarget:(id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands>)target configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBLogicXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
      return nil;
  }

  _target = target;
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

  return [[FBFuture
    futureWithFutures:@[
      [self buildOutputsForUUID:uuid],
      [self.target extendedTestShim],
    ]]
    onQueue:self.target.workQueue fmap:^(NSArray<id> *tuple) {
      return [self testFutureWithOutputs:tuple[0] shimPath:tuple[1] uuid:uuid];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)testFutureWithOutputs:(FBLogicTestRunOutputs *)outputs shimPath:(NSString *)shimPath uuid:(NSUUID *)uuid
{
  [self.logger logFormat:@"Starting Logic Test execution of %@", self.configuration];
  id<FBLogicXCTestReporter> reporter = self.reporter;
  [reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.target.xctestPath;

  // Get the Launch Path and Arguments for the xctest process.
  NSString *testSpecifier = self.configuration.testFilter ?: @"All";
  NSString *launchPath = xctestPath;
  NSArray<NSString *> *arguments = @[@"-XCTest", testSpecifier, self.configuration.testBundlePath];

  return [[FBOToolDynamicLibs
    findFullPathForSanitiserDyldInBundle:self.configuration.testBundlePath onQueue:self.target.workQueue]
    onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> * (NSArray<NSString *> *libraries) {
      NSDictionary<NSString *, NSString *> *environment = [self setupEnvironmentWithDylibs:[self.configuration.processUnderTestEnvironment mutableCopy]
        withLibraries:libraries
        shimOutputFilePath:outputs.shimOutput.filePath
        shimPath:shimPath
        bundlePath:self.configuration.testBundlePath
        coveragePath:self.configuration.coveragePath
        waitForDebugger:self.configuration.waitForDebugger];

      return [[self
        startTestProcessWithLaunchPath:launchPath arguments:arguments environment:environment outputs:outputs]
        onQueue:self.target.workQueue fmap:^(FBFuture<NSNumber *> *exitCode) {
          return [self completeLaunchedProcess:exitCode outputs:outputs];
        }];
    }];
}

- (NSDictionary<NSString *, NSString *> *)setupEnvironmentWithDylibs:(NSDictionary<NSString *, NSString *> *)environment withLibraries:(NSArray *)libraries shimOutputFilePath:(NSString *)shimOutputFilePath shimPath:(NSString *)shimPath bundlePath:(NSString *)bundlePath coveragePath:(nullable NSString *)coveragePath waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, NSString *> *updatedEnvironment = [NSMutableDictionary dictionaryWithDictionary:environment];

  NSMutableArray *librariesWithShim = [NSMutableArray arrayWithObject:shimPath];
  [librariesWithShim addObjectsFromArray:libraries];
  updatedEnvironment[@"DYLD_INSERT_LIBRARIES"] = [librariesWithShim componentsJoinedByString:@":"];
  updatedEnvironment[@"TEST_SHIM_STDOUT_PATH"] = shimOutputFilePath;
  updatedEnvironment[@"TEST_SHIM_BUNDLE_PATH"] = bundlePath;
  if (coveragePath) {
    updatedEnvironment[@"LLVM_PROFILE_FILE"] = coveragePath;
  }

  updatedEnvironment[@"XCTOOL_WAIT_FOR_DEBUGGER"] = waitForDebugger ? @"YES" : @"NO";

  return [NSDictionary dictionaryWithDictionary:updatedEnvironment];
}

- (FBFuture<NSNull *> *)completeLaunchedProcess:(FBFuture<NSNumber *> *)exitCode outputs:(FBLogicTestRunOutputs *)outputs
{
  id<FBControlCoreLogger> logger = self.logger;
  id<FBLogicXCTestReporter> reporter = self.reporter;
  dispatch_queue_t queue = self.target.workQueue;

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
  dispatch_queue_t queue = self.target.workQueue;
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
        NSString *stdErrReversed = [outputs.stdErrBuffer.lines.reverseObjectEnumerator.allObjects componentsJoinedByString:@"\n"];
        return [[FBControlCoreError
          describeFormat:@"xctest process exited in failure (%d): %@ %@", exitCodeValue, descriptionOfExit, stdErrReversed]
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
  dispatch_queue_t queue = self.target.workQueue;
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
  id<FBConsumableBuffer> stdErrBuffer = FBDataBuffer.consumableBuffer;
  [stdErrConsumers addObject:stdErrBuffer];

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
    FBXCTestLogger *mirrorLogger = self.configuration.logDirectoryPath ? [FBXCTestLogger defaultLoggerInDirectory:self.configuration.logDirectoryPath] : [FBXCTestLogger defaultLoggerInDefaultDirectory];
    stdOutFuture = [mirrorLogger logConsumptionToFile:stdOutConsumer outputKind:@"out" udid:udid logger:logger];
    stdErrFuture = [mirrorLogger logConsumptionToFile:stdErrConsumer outputKind:@"err" udid:udid logger:logger];
    shimFuture = [mirrorLogger logConsumptionToFile:shimConsumer outputKind:@"shim" udid:udid logger:logger];
  }
  return [[FBFuture
    futureWithFutures:@[
      stdOutFuture, stdErrFuture, shimFuture
    ]]
    onQueue:self.target.workQueue fmap:^(NSArray<id<FBDataConsumer, FBDataConsumerLifecycle>> *outputs) {
      return [[[FBProcessOutput
        outputForDataConsumer:outputs[2]]
        providedThroughFile]
        onQueue:self.target.workQueue map:^(id<FBProcessFileOutput> shimOutput) {
          return [[FBLogicTestRunOutputs alloc] initWithStdOutConsumer:outputs[0] stdErrConsumer:outputs[1] stdErrBuffer:stdErrBuffer shimConsumer:outputs[2] shimOutput:shimOutput];
        }];
    }];
}

- (FBFuture<FBFuture<NSNumber *> *> *)startTestProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment outputs:(FBLogicTestRunOutputs *)outputs
{
  dispatch_queue_t queue = self.target.workQueue;
  id<FBControlCoreLogger> logger = self.logger;
  id<FBLogicXCTestReporter> reporter = self.reporter;
  NSTimeInterval timeout = self.configuration.testTimeout;

  [logger logFormat:
    @"Launching xctest process with arguments %@, environment %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[@[launchPath] arrayByAddingObjectsFromArray:arguments]],
    [FBCollectionInformation oneLineDescriptionFromDictionary:environment]
  ];
  FBProcessIO *io = [[FBProcessIO alloc] initWithStdIn:nil stdOut:[FBProcessOutput outputForDataConsumer:outputs.stdOutConsumer] stdErr:[FBProcessOutput outputForDataConsumer:outputs.stdErrConsumer]];
  FBProcessSpawnConfiguration *configuration = [[FBProcessSpawnConfiguration alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment io:io mode:FBProcessSpawnModeDefault];

  return [[self.target
    launchProcess:configuration]
    onQueue:queue map:^ FBFuture<NSNumber *> * (id<FBLaunchedProcess> process) {
      return [[FBLogicTestRunStrategy
        fromQueue:queue waitForDebuggerToBeAttached:self.configuration.waitForDebugger forProcessIdentifier:process.processIdentifier reporter:reporter]
        onQueue:queue fmap:^(id _) {
          return [FBXCTestProcess ensureProcess:process completesWithin:timeout withCrashLogDetection:YES queue:queue logger:logger];
        }];
    }];
}

@end
