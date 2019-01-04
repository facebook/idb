/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlOperator.h"

#import <CoreSimulator/SimDevice.h>

#import <DTXConnectionServices/DTXSocketTransport.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import <sys/socket.h>
#import <sys/un.h>

#import <objc/runtime.h>

#import <XCTestBootstrap/FBProductBundle.h>

#import "FBSimulatorError.h"

@interface FBSimulatorControlOperator ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorControlOperator

+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator
{
  return [[FBSimulatorControlOperator alloc] initWithSimulator:simulator];
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

#pragma mark - FBApplicationCommands

- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path
{
  return [self.simulator installApplicationWithPath:path];
}

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [self.simulator isApplicationInstalledWithBundleID:bundleID];
}

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
    return [self.simulator launchApplication:configuration];
}

#pragma mark - FBDeviceOperator protocol

- (FBFuture<DTXTransport *> *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger
{
  const BOOL simulatorIsBooted = (self.simulator.state == FBiOSTargetStateBooted);
  if (!simulatorIsBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator should be already booted"]
      logger:logger]
      failFuture];
  }

  NSError *innerError;
  int testManagerSocket = [self makeTestManagerDaemonSocketWithLogger:logger error:&innerError];
  if (testManagerSocket == 1) {
    return [[[[FBSimulatorError
      describe:@"Falied to create test manager dameon socket"]
      causedBy:innerError]
      logger:logger]
      failFuture];
  }

  DTXSocketTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:testManagerSocket disconnectAction:^{
    [logger log:@"Disconnected from test manager daemon socket"];
  }];
  if (!transport) {
    return [[FBSimulatorError
      describeFormat:@"Could not create a DTXSocketTransport for %d", testManagerSocket]
      failFuture];
  }

  return [FBFuture futureWithResult:transport];
}

- (int)makeTestManagerDaemonSocketWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
  if (socketFD == -1) {
    [[[FBSimulatorError
       describe:@"Unable to create a unix domain socket"]
      logger:logger]
     failUInt:error];
    return -1;
  }

  NSString *testManagerSocketString = [self testManagerDaemonSocketPathWithLogger:logger];
  if (testManagerSocketString.length == 0) {
    [[[FBSimulatorError
       describe:@"Failed to retrieve testmanagerd socket path"]
      logger:logger]
     failUInt:error];
    return -1;
  }

  if (![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
    [[[FBSimulatorError
       describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
      logger:logger]
     fail:error];
    return -1;
  }

  const char *testManagerSocketPath = testManagerSocketString.UTF8String;
  if (strlen(testManagerSocketPath) >= 0x68) {
    [[[FBSimulatorError
       describeFormat:@"Unix domain socket path for simulator testmanagerd service '%s' is too big to fit in sockaddr_un.sun_path", testManagerSocketPath]
      logger:logger]
     fail:error];
    return -1;
  }

  struct sockaddr_un remote;
  remote.sun_family = AF_UNIX;
  strcpy(remote.sun_path, testManagerSocketPath);
  socklen_t length = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + sizeof(remote.sun_len));
  if (connect(socketFD, (struct sockaddr *)&remote, length) == -1) {
    [[[FBSimulatorError
       describe:@"Failed to connect to testmangerd socket"]
      logger:logger]
     fail:error];
    return -1;
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

- (BOOL)requiresTestDaemonMediationForTestHostConnection
{
  return YES;
}

- (BOOL)launchApplicationWithBundleID:(NSString *)bundleID arguments:(NSArray *)arguments environment:(NSDictionary *)environment waitForDebugger:(BOOL)waitForDebugger error:(NSError **)error
{
  FBInstalledApplication *app = [[self.simulator installedApplicationWithBundleID:bundleID] await:error];
  if (!app) {
    return NO;
  }

  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration
    configurationWithBundleID:app.bundle.bundleID
    bundleName:app.bundle.name
    arguments:arguments
    environment:environment
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:FBApplicationLaunchModeRelaunchIfRunning];
  if (waitForDebugger) {
    configuration = [configuration withWaitForDebugger:error];
    if (*error) {
      return NO;
    }
  }

  if (![[self.simulator launchApplication:configuration] await:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [[self.simulator killApplicationWithBundleID:bundleID] await:error] != nil;
}

- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID
{
  return [[self.simulator
    serviceNameAndProcessIdentifierForSubstring:bundleID]
    onQueue:self.simulator.asyncQueue fmap:^(NSArray<id> *result) {
      NSNumber *processIdentifier = result[1];
      if (processIdentifier.intValue < 1) {
        return [[FBSimulatorError
          describeFormat:@"Service %@ does not have a running process", result[0]]
          failFuture];
      }
      return [FBFuture futureWithResult:processIdentifier];
    }];
}

@end
