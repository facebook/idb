/**
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
  return [self startTestWithLaunchConfiguration:testLaunchConfiguration reporter:reporter logger:logger workingDirectory:self.simulator.auxillaryDirectory];
}

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

- (FBFuture<NSNull *> *)runApplicationTest:(FBTestManagerTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter
{
  return [[FBTestRunStrategy
    strategyWithTarget:self.simulator configuration:configuration reporter:reporter logger:self.simulator.logger testPreparationStrategyClass:FBSimulatorTestPreparationStrategy.class]
    execute];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  return [[FBXCTestShimConfiguration
    defaultShimConfiguration]
    onQueue:self.simulator.workQueue fmap:^(FBXCTestShimConfiguration *shims) {
      FBListTestConfiguration *configuration = [FBListTestConfiguration
        configurationWithShims:shims
        environment:@{}
        workingDirectory:self.simulator.auxillaryDirectory
        testBundlePath:bundlePath
        runnerAppPath:nil
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
  NSFileHandle *testManagerSocket = [self makeTestManagerDaemonSocketWithLogger:self.simulator.logger error:&innerError];
  if (!testManagerSocket) {
    return [[[[FBSimulatorError
      describe:@"Falied to create test manager dameon socket"]
      causedBy:innerError]
      logger:self.simulator.logger]
      failFutureContext];
  }

  return [[FBFuture
    futureWithResult:@(testManagerSocket.fileDescriptor)]
    onQueue:self.simulator.workQueue contextualTeardown:^(id _, FBFutureState __) {
      [testManagerSocket closeFile];
    }];
}

#pragma mark Private

- (NSFileHandle *)makeTestManagerDaemonSocketWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
  if (socketFD == -1) {
    return [[[FBSimulatorError
      describe:@"Unable to create a unix domain socket"]
      logger:logger]
      fail:error];
  }

  NSString *testManagerSocketString = [self testManagerDaemonSocketPathWithLogger:logger];
  if (testManagerSocketString.length == 0) {
    return [[[FBSimulatorError
      describe:@"Failed to retrieve testmanagerd socket path"]
      logger:logger]
      fail:error];
  }

  if (![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
    return [[[FBSimulatorError
      describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
      logger:logger]
      fail:error];
  }

  const char *testManagerSocketPath = testManagerSocketString.UTF8String;
  if (strlen(testManagerSocketPath) >= 0x68) {
    return [[[FBSimulatorError
      describeFormat:@"Unix domain socket path for simulator testmanagerd service '%s' is too big to fit in sockaddr_un.sun_path", testManagerSocketPath]
      logger:logger]
      fail:error];
  }

  struct sockaddr_un remote;
  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, testManagerSocketPath);
  socklen_t length = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + sizeof(remote.sun_len));
  if (connect(socketFD, (struct sockaddr *)&remote, length) == -1) {
    return [[[FBSimulatorError
      describe:@"Failed to connect to testmangerd socket"]
      logger:logger]
      fail:error];
  }
  return [[NSFileHandle alloc] initWithFileDescriptor:socketFD];
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
