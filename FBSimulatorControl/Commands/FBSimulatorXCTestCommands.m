/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorXCTestCommands.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <sys/socket.h>
#import <sys/un.h>

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorXCTestProcessExecutor.h"
#import "FBSimulatorTestPreparationStrategy.h"

@interface FBSimulatorXCTestCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, nullable, readwrite) id<FBiOSTargetContinuation> operation;

@end

@implementation FBSimulatorXCTestCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Public

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  // Use FBXCTestBootstrap to run the test if `shouldUseXcodebuild` is not set in the test launch.
  if (!testLaunchConfiguration.shouldUseXcodebuild) {
    return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger workingDirectory:self.simulator.auxillaryDirectory];
  }

  if (self.operation) {
    return [[FBSimulatorError
      describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
      failFuture];
  }
  return [[[FBXcodeBuildOperation
    terminateAbandonedXcodebuildProcessesForUDID:self.simulator.udid processFetcher:[FBProcessFetcher new] queue:self.simulator.workQueue logger:logger]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      return [self _startTestWithLaunchConfiguration:testLaunchConfiguration logger:logger];
    }]
    onQueue:self.simulator.workQueue map:^(FBTask *task) {
      return [self _testOperationStarted:task configuration:testLaunchConfiguration reporter:reporter logger:logger];
    }];
}

- (FBFuture<FBTask *> *)_startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  NSString *filePath = [FBXcodeBuildOperation createXCTestRunFileAt:self.simulator.auxillaryDirectory fromConfiguration:configuration error:&error];
  if (!filePath) {
    return [FBSimulatorError failFutureWithError:error];
  }

  NSString *xcodeBuildPath = [FBXcodeBuildOperation xcodeBuildPathWithError:&error];
  if (!xcodeBuildPath) {
    return [FBSimulatorError failFutureWithError:error];
  }

  return [FBXcodeBuildOperation
    operationWithUDID:self.simulator.udid
    configuration:configuration
    xcodeBuildPath:xcodeBuildPath
    testRunFilePath:filePath
    queue:self.simulator.workQueue
    logger:[logger withName:@"xcodebuild"]];
}

- (id<FBiOSTargetContinuation>)_testOperationStarted:(FBTask *)task configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNull *> *completed = [[[[task
    completed]
    onQueue:self.simulator.workQueue fmap:^FBFuture<NSNull *> *(id _) {
      [logger logFormat:@"xcodebuild operation completed successfully %@", task];
      if (configuration.resultBundlePath) {
        [FBXCTestResultBundleParser parse:configuration.resultBundlePath target:self.simulator reporter:reporter logger:logger];
      }
      [logger log:@"No result bundle to parse"];
      return FBFuture.empty;
    }]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      [reporter testManagerMediatorDidFinishExecutingTestPlan:nil];
      return FBFuture.empty;
    }]
    onQueue:self.simulator.workQueue chain:^(FBFuture *future) {
      [logger logFormat:@"Test Operation has completed for %@, with state '%@' removing it as the sole operation for this target", future, configuration.shortDescription];
      self.operation = nil;
      return future;
    }];

  self.operation = FBiOSTargetContinuationNamed(completed, FBiOSTargetFutureTypeTestOperation);
  [logger logFormat:@"Test Operation %@ has started for %@, storing it as the sole operation for this target", task, configuration.shortDescription];

  return self.operation;
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(NSString *)appPath
{
  return [[FBXCTestShimConfiguration
    defaultShimConfiguration]
    onQueue:self.simulator.workQueue fmap:^(FBXCTestShimConfiguration *shims) {
      FBListTestConfiguration *configuration = [FBListTestConfiguration
        configurationWithShims:shims
        environment:@{}
        workingDirectory:self.simulator.auxillaryDirectory
        testBundlePath:bundlePath
        runnerAppPath:appPath
        waitForDebugger:NO
        timeout:timeout];

      return [[FBListTestStrategy
        strategyWithExecutor:[FBSimulatorXCTestProcessExecutor executorWithSimulator:self.simulator shims:configuration.shims]
        configuration:configuration
        logger:self.simulator.logger]
        listTests];
  }];
}

- (FBFutureContext<NSNumber *> *)transportForTestManagerService
{
  const BOOL simulatorIsBooted = (self.simulator.state == FBiOSTargetStateBooted);
  if (!simulatorIsBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator should be already booted"]
      logger:self.simulator.logger]
      failFutureContext];
  }

  NSError *innerError;
  int testManagerSocket = [self makeTestManagerDaemonSocketWithLogger:self.simulator.logger error:&innerError];
  if (testManagerSocket < 1) {
    return [[[[FBSimulatorError
      describe:@"Falied to create test manager dameon socket"]
      causedBy:innerError]
      logger:self.simulator.logger]
      failFutureContext];
  }

  return [[FBFuture
    futureWithResult:@(testManagerSocket)]
    onQueue:self.simulator.workQueue contextualTeardown:^(id _, FBFutureState __) {
      close(testManagerSocket);
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger workingDirectory:(nullable NSString *)workingDirectory
{
  if (self.simulator.state != FBiOSTargetStateBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator must be booted to run tests"]
      inSimulator:self.simulator]
      failFuture];
  }
  FBSimulatorTestPreparationStrategy *testPreparationStrategy = [FBSimulatorTestPreparationStrategy
    strategyWithTestLaunchConfiguration:testLaunchConfiguration
    workingDirectory:workingDirectory];
  return (FBFuture<id<FBiOSTargetContinuation>> *) [[FBManagedTestRunStrategy
    strategyWithTarget:self.simulator configuration:testLaunchConfiguration reporter:reporter logger:logger testPreparationStrategy:testPreparationStrategy]
    connectAndStart];
}

- (int)makeTestManagerDaemonSocketWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
  if (socketFD == -1) {
    return [[[FBSimulatorError
      describe:@"Unable to create a unix domain socket"]
      logger:logger]
      failInt:error];
  }

  NSString *testManagerSocketString = [self testManagerDaemonSocketPathWithLogger:logger];
  if (testManagerSocketString.length == 0) {
    close(socketFD);
    return [[[FBSimulatorError
      describe:@"Failed to retrieve testmanagerd socket path"]
      logger:logger]
      failInt:error];
  }

  if (![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
    close(socketFD);
    return [[[FBSimulatorError
      describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
      logger:logger]
      failInt:error];
  }

  const char *testManagerSocketPath = testManagerSocketString.UTF8String;
  if (strlen(testManagerSocketPath) >= 0x68) {
    close(socketFD);
    return [[[FBSimulatorError
      describeFormat:@"Unix domain socket path for simulator testmanagerd service '%s' is too big to fit in sockaddr_un.sun_path", testManagerSocketPath]
      logger:logger]
      failInt:error];
  }

  struct sockaddr_un remote;
  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, testManagerSocketPath);
  socklen_t length = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + sizeof(remote.sun_len));
  if (connect(socketFD, (struct sockaddr *)&remote, length) == -1) {
    close(socketFD);
    return [[[FBSimulatorError
      describe:@"Failed to connect to testmangerd socket"]
      logger:logger]
      failInt:error];
  }
  return socketFD;
}

- (NSString *)testManagerDaemonSocketPathWithLogger:(id<FBControlCoreLogger>)logger
{
  const NSUInteger maxTryCount = 10;
  NSUInteger tryCount = 0;
  do {
    NSString *socketPath = [self.simulator.device getenv:@"TESTMANAGERD_SIM_SOCK" error:nil];
    if (socketPath.length > 0) {
      return socketPath;
    }
    [logger logFormat:@"Simulator is booted but getenv returned nil for test connection socket path.\n Will retry in 1s (%lu attempts so far).", (unsigned long)tryCount];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
  } while (tryCount++ >= maxTryCount);
  return nil;
}

@end
