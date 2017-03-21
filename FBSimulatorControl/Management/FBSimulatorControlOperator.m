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
@property (nonatomic, strong) FBSimulator *simulator;
@end

@implementation FBSimulatorControlOperator

+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator
{
  FBSimulatorControlOperator *operator = [self.class new];
  operator.simulator = simulator;
  return operator;
}

- (NSString *)udid
{
  return self.simulator.udid;
}

#pragma mark - FBApplicationCommands

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  FBApplicationDescriptor *application = [FBApplicationDescriptor userApplicationWithPath:path error:error];
  if (![self.simulator installApplicationWithPath:application.path error:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return ([self.simulator installedApplicationWithBundleID:bundleID error:error] != nil);
}

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration error:(NSError **)error
{
  return [self.simulator launchApplication:configuration error:error];
}

#pragma mark - FBDeviceOperator protocol

- (DTXTransport *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if ([NSThread isMainThread]) {
    return [[[FBSimulatorError
      describe:@"'makeTransportForTestManagerService' method may block and should not be called on the main thread"]
      logger:logger]
      fail:error];
  }

  const BOOL simulatorIsBooted = (self.simulator.state == FBSimulatorStateBooted);
  if (!simulatorIsBooted) {
    return [[[FBSimulatorError
      describe:@"Simulator should be already booted"]
      logger:logger]
      fail:error];
  }

  NSError *innerError;
  int testManagerSocket = [self makeTestManagerDaemonSocketWithLogger:logger error:&innerError];
  if (testManagerSocket == 1) {
    return [[[[FBSimulatorError
      describe:@"Falied to create test manager dameon socket"]
      causedBy:innerError]
      logger:logger]
      fail:error];
  }

  DTXSocketTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:testManagerSocket disconnectAction:^{
    [logger log:@"Disconnected from test manager daemon socket"];
  }];
  if (!transport) {
    return [[FBSimulatorError
      describeFormat:@"Could not create a DTXSocketTransport for %d", testManagerSocket]
      fail:error];
  }

  return transport;
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
  if(testManagerSocketString.length == 0) {
    [[[FBSimulatorError
       describe:@"Failed to retrieve testmanagerd socket path"]
      logger:logger]
     failUInt:error];
    return -1;
  }

  if(![[NSFileManager new] fileExistsAtPath:testManagerSocketString]) {
    [[[FBSimulatorError
       describeFormat:@"Simulator indicated unix domain socket for testmanagerd at path %@, but no file was found at that path.", testManagerSocketString]
      logger:logger]
     fail:error];
    return -1;
  }

  const char *testManagerSocketPath = testManagerSocketString.UTF8String;
  if(strlen(testManagerSocketPath) >= 0x68) {
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

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError **)error
{
  return YES;
}

- (FBProductBundle *)applicationBundleWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBApplicationDescriptor *application = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!application) {
    return nil;
  }

  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builder]
    withBundlePath:application.path]
   buildWithError:error];

  return productBundle;
}

- (BOOL)launchApplicationWithBundleID:(NSString *)bundleID arguments:(NSArray *)arguments environment:(NSDictionary *)environment waitForDebugger:(BOOL)waitForDebugger error:(NSError **)error
{
  FBApplicationDescriptor *app = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!app) {
    return NO;
  }

  FBApplicationLaunchConfiguration *configuration = [FBApplicationLaunchConfiguration
    configurationWithApplication:app
    arguments:arguments
    environment:environment
    waitForDebugger:waitForDebugger
    output:FBProcessOutputConfiguration.outputToDevNull];

  if (![self.simulator launchOrRelaunchApplication:configuration error:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.simulator killApplicationWithBundleID:bundleID error:error];
}

- (pid_t)processIDWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  pid_t processIdentifier = 0;
  NSString *serviceName = [self.simulator.launchctl serviceNameForBundleID:bundleID processIdentifierOut:&processIdentifier error:error];
  if (!serviceName) {
    return -1;
  }
  if (processIdentifier < 1) {
    [[FBSimulatorError
      describeFormat:@"Found the Process for %@ with service name %@ but the process was not alive", bundleID, serviceName]
      fail:error];
  }
  return processIdentifier;
}

- (nullable FBDiagnostic *)attemptToFindCrashLogForProcess:(pid_t)pid bundleID:(NSString *)bundleID
{
  return [[self.simulator.simulatorDiagnostics userLaunchedProcessCrashesSinceLastLaunchWithProcessIdentifier:pid] firstObject];
}

#pragma mark - Unsupported FBDeviceOperator protocol method

- (BOOL)cleanApplicationStateWithBundleIdentifier:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"cleanApplicationStateWithBundleIdentifier is not yet supported");
  return NO;
}

- (NSString *)applicationPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"applicationPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (BOOL)uploadApplicationDataAtPath:(NSString *)path bundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"uploadApplicationDataAtPath is not yet supported");
  return NO;
}

- (NSString *)containerPathForApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSAssert(nil, @"containerPathForApplicationWithBundleID is not yet supported");
  return nil;
}

- (NSString *)consoleString
{
  NSAssert(nil, @"consoleString is not yet supported");
  return nil;
}

@end
