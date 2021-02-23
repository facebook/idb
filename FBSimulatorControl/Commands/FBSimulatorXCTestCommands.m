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
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorXCTestProcessExecutor.h"
#import "FBSimulatorTestPreparationStrategy.h"

static NSString *const DefaultSimDeviceSet = @"~/Library/Developer/CoreSimulator/Devices";

@interface FBSimulatorXCTestCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, assign, readwrite) BOOL isRunningXcodeBuildOperation;

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

- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  // Use FBXCTestBootstrap to run the test if `shouldUseXcodebuild` is not set in the test launch.
  if (!testLaunchConfiguration.shouldUseXcodebuild) {
    return [self runTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger workingDirectory:self.simulator.auxillaryDirectory];
  }

  if (self.isRunningXcodeBuildOperation) {
    return [[FBSimulatorError
      describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
      failFuture];
  }
  return [[[[FBXcodeBuildOperation
    terminateAbandonedXcodebuildProcessesForUDID:self.simulator.udid processFetcher:[FBProcessFetcher new] queue:self.simulator.workQueue logger:logger]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      self.isRunningXcodeBuildOperation = YES;
      return [self _startTestWithLaunchConfiguration:testLaunchConfiguration logger:logger];
    }]
    onQueue:self.simulator.workQueue map:^(FBTask *task) {
      return [self _testOperationStarted:task configuration:testLaunchConfiguration reporter:reporter logger:logger];
    }]
    onQueue:self.simulator.workQueue chain:^(FBFuture *future) {
      self.isRunningXcodeBuildOperation = NO;
      return future;
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
    simDeviceSet:[self.simulator.device.deviceSet.setPath isEqualToString:[DefaultSimDeviceSet stringByExpandingTildeInPath]] ? nil : self.simulator.device.deviceSet.setPath
    queue:self.simulator.workQueue
    logger:[logger withName:@"xcodebuild"]];
}

- (FBFuture<NSNull * > *)_testOperationStarted:(FBTask *)task configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [[[task
    completed]
    onQueue:self.simulator.workQueue fmap:^FBFuture<NSNull *> *(id _) {
      [logger logFormat:@"xcodebuild operation completed successfully %@", task];
      if (configuration.resultBundlePath) {
        return [FBXCTestResultBundleParser parse:configuration.resultBundlePath target:self.simulator reporter:reporter logger:logger];
      }
      [logger log:@"No result bundle to parse"];
      return FBFuture.empty;
    }]
    onQueue:self.simulator.workQueue fmap:^(id _) {
      [reporter didFinishExecutingTestPlan];
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(NSString *)appPath
{
  return [[FBXCTestShimConfiguration
    defaultShimConfigurationWithLogger:self.simulator.logger]
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
  return [[[self
    testManagerDaemonSocketPath]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNumber *> * (NSString *testManagerSocketString) {
      int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
      if (socketFD == -1) {
        return [[FBSimulatorError
          describe:@"Unable to create a unix domain socket"]
          failFuture];
      }
      if (![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
        close(socketFD);
        return [[FBSimulatorError
          describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
          failFuture];
      }

      const char *testManagerSocketPath = testManagerSocketString.UTF8String;
      if (strlen(testManagerSocketPath) >= 0x68) {
        close(socketFD);
        return [[FBSimulatorError
          describeFormat:@"Unix domain socket path for simulator testmanagerd service '%s' is too big to fit in sockaddr_un.sun_path", testManagerSocketPath]
          failFuture];
      }

      struct sockaddr_un remote;
      remote.sun_family = AF_UNIX;
      strcpy(remote.sun_path, testManagerSocketPath);
      socklen_t length = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + sizeof(remote.sun_len));
      if (connect(socketFD, (struct sockaddr *)&remote, length) == -1) {
        close(socketFD);
        return [[FBSimulatorError
          describe:@"Failed to connect to testmangerd socket"]
          failFuture];
      }
      return [FBFuture futureWithResult:@(socketFD)];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(NSNumber *socketNumber, FBFutureState __) {
      close(socketNumber.intValue);
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger workingDirectory:(nullable NSString *)workingDirectory
{
  if (self.simulator.state != FBiOSTargetStateBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator must be booted to run tests"]
      inSimulator:self.simulator]
      failFuture];
  }
  return [[FBXCTestShimConfiguration
    defaultShimConfigurationWithLogger:self.simulator.logger]
    onQueue:self.simulator.workQueue fmap:^(FBXCTestShimConfiguration *shims) {
      FBSimulatorTestPreparationStrategy *testPreparationStrategy = [[FBSimulatorTestPreparationStrategy alloc]
        initWithTestLaunchConfiguration:testLaunchConfiguration
        shims:shims
        workingDirectory:self.simulator.auxillaryDirectory
        codesign:[FBCodesignProvider codeSignCommandWithAdHocIdentityWithLogger:self.simulator.logger]];

      return [FBManagedTestRunStrategy
        runToCompletionWithTarget:self.simulator
        configuration:testLaunchConfiguration
        reporter:reporter
        testPreparationStrategy:testPreparationStrategy
        logger:logger];
    }];
}

static NSTimeInterval const TestmanagerdSimSockTimeout = 5; // 5 seconds.
static NSString *const SimSockEnvKey = @"TESTMANAGERD_SIM_SOCK";

- (FBFuture<NSString *> *)testManagerDaemonSocketPath
{
  return [[FBFuture
    onQueue:self.simulator.asyncQueue resolveUntil:^{
      NSError *error = nil;
      NSString *socketPath = [self.simulator.device getenv:SimSockEnvKey error:&error];
      if (socketPath.length == 0) {
        return [[[FBSimulatorError
          describeFormat:@"Failed to get %@ from simulator environment", SimSockEnvKey]
          causedBy:error]
          failFuture];
      }
      return [FBFuture futureWithResult:socketPath];
    }]
    timeout:TestmanagerdSimSockTimeout waitingFor:@"%@ to become available in the simulator environment", SimSockEnvKey];
}

@end
