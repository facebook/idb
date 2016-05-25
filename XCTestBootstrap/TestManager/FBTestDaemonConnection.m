/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestDaemonConnection.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <FBControlCore/FBControlCore.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerAPIMediator.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestDaemonConnection () <XCTestManager_IDEInterface>

@property (atomic, assign, readwrite) FBTestDaemonConnectionState state;
@property (atomic, strong, readwrite) XCTestBootstrapError *error;

@property (atomic, assign, readwrite) long long daemonProtocolVersion;
@property (atomic, nullable, strong, readwrite) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (atomic, nullable, strong, readwrite) DTXConnection *daemonConnection;

@end

@implementation FBTestDaemonConnection

#pragma mark Initializers

+ (instancetype)withDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDevice:device interface:interface testRunnerPID:testRunnerPID queue:queue logger:logger];
}

- (instancetype)initWithDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _interface = interface;
  _queue = queue;
  _testRunnerPID = testRunnerPID;
  _logger = logger;

  _state = FBTestDaemonConnectionStateNotConnected;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Test Daemon Connection %@",
    [FBTestDaemonConnection stringForDaemonConnectionState:self.state]
  ];
}

#pragma mark Delegate Forwarding

- (BOOL)respondsToSelector:(SEL)selector
{
  return [super respondsToSelector:selector] || [self.interface respondsToSelector:selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [(id)self.interface methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.interface respondsToSelector:invocation.selector]) {
    [invocation invokeWithTarget:self.interface];
  } else {
    [super forwardInvocation:invocation];
  }
}

#pragma mark Public

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (self.state != FBTestDaemonConnectionStateNotConnected) {
    return [[XCTestBootstrapError
      describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateNotConnected], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]]
      failBool:error];
  }

  [self connect];
  BOOL waitSuccess = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.state != FBTestDaemonConnectionStateConnecting;
  }];

  if (!waitSuccess) {
    return [[[XCTestBootstrapError
      describeFormat:@"Timed out waiting for daemon connection"]
      causedBy:self.error.build]
      failBool:error];
  }
  if (self.state != FBTestDaemonConnectionStateReadyToExecuteTestPlan) {
    return [[[XCTestBootstrapError
      describe:@"Failed to connect to daemon"]
      causedBy:self.error.build]
      failBool:error];
  }
  return YES;
}

- (void)disconnect
{
  [self.logger logFormat:@"Disconnecting Daemon from state '%@'", [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];

  if (self.state != FBTestDaemonConnectionStateFinishedInError) {
    self.state = FBTestDaemonConnectionStateFinishedSuccessfully;
  }
  [self.daemonConnection suspend];
  [self.daemonConnection cancel];
  self.daemonConnection = nil;
  self.daemonProxy = nil;
  self.daemonProtocolVersion = 0;
}

- (BOOL)notifyTestPlanStartedWithError:(NSError **)error
{
  if (self.state != FBTestDaemonConnectionStateReadyToExecuteTestPlan) {
    return [[[XCTestBootstrapError
      describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateReadyToExecuteTestPlan], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]]
      logger:self.logger]
      failBool:error];
  }

  [self.logger log:@"Daemon Notified of start of test plan"];
  self.state = FBTestDaemonConnectionStateRunningTestPlan;
  return YES;
}

- (BOOL)notifyTestPlanEndedWithError:(NSError **)error
{
  if (self.state != FBTestDaemonConnectionStateRunningTestPlan) {
    return [[[XCTestBootstrapError
      describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateRunningTestPlan], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]]
      logger:self.logger]
      failBool:error];
  }

  [self.logger log:@"Daemon Notified of end of test plan"];
  self.state = FBTestDaemonConnectionStateEndedTestPlan;
  return YES;
}

#pragma mark Private

- (void)connect
{
  self.state = FBTestDaemonConnectionStateConnecting;
  [self.logger log:@"Starting the daemon connection"];
  dispatch_async(self.queue, ^{
    NSError *innerError = nil;
    DTXTransport *transport = [self.device makeTransportForTestManagerService:&innerError];
    if (innerError || !transport) {
      [self failWithError:[[XCTestBootstrapError
        describe:@"Failed to created secondary test manager transport"]
        causedBy:innerError]];
    }
    [self createDaemonConnectionWithTransport:transport];
  });
}

- (DTXConnection *)createDaemonConnectionWithTransport:(DTXTransport *)transport
{
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    FBTestDaemonConnectionState state = self.state;
    [self.logger logFormat:@"Daemon Connection Disconnected in state '%@'", [FBTestDaemonConnection stringForDaemonConnectionState:state]];
    if (state == FBTestDaemonConnectionStateEndedTestPlan ||
        state == FBTestDaemonConnectionStateFinishedSuccessfully ||
        state == FBTestDaemonConnectionStateFinishedInError) {
      return;
    }
    [self failWithError:[XCTestBootstrapError
      describeFormat:@"Disconnected with state %@", [FBTestDaemonConnection stringForDaemonConnectionState:state]]];
  }];
  [self.logger logFormat:@"Resuming the daemon connection."];
  self.daemonConnection = connection;

  [connection resume];
  DTXProxyChannel *channel = [connection
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [channel setExportedObject:self queue:dispatch_get_main_queue()];
  self.daemonProxy = (id<XCTestManager_DaemonConnectionInterface>)channel.remoteObjectProxy;

  [self.logger logFormat:@"Whitelisting test process ID %d", self.testRunnerPID];
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID) protocolVersion:@(FBProtocolVersion)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [self.logger log:@"Error in establishing daemon connection, trying legacy protocol"];
      [self setupDaemonConnectionViaLegacyProtocol];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self.logger logFormat:@"Got whitelisting response and daemon protocol version %lld", self.daemonProtocolVersion];
    [self.logger log:@"Ready to execute test plan"];
    self.state = FBTestDaemonConnectionStateReadyToExecuteTestPlan;
  }];
  return connection;
}

- (DTXRemoteInvocationReceipt *)setupDaemonConnectionViaLegacyProtocol
{
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [self.logger logFormat:@"Error in whitelisting response from testmanagerd: %@ (%@), ignoring for now.", error.localizedDescription, error.localizedRecoverySuggestion];
    } else {
      self.daemonProtocolVersion = version.integerValue;
      [self.logger logFormat:@"Got legacy whitelisting response, daemon protocol version is 14"];
    }
    [self.logger log:@"Daemon Connection connected via legacy protocol"];
    self.state = FBTestDaemonConnectionStateReadyToExecuteTestPlan;
  }];
  return receipt;
}

+ (NSString *)stringForDaemonConnectionState:(FBTestDaemonConnectionState)state
{
  switch (state) {
    case FBTestDaemonConnectionStateNotConnected:
      return @"not connected";
    case FBTestDaemonConnectionStateConnecting:
      return @"connecting";
    case FBTestDaemonConnectionStateReadyToExecuteTestPlan:
      return @"ready to execute test plan";
    case FBTestDaemonConnectionStateRunningTestPlan:
      return @"executing test plan";
    case FBTestDaemonConnectionStateEndedTestPlan:
      return @"ended test plan";
    case FBTestDaemonConnectionStateFinishedSuccessfully:
      return @"finished succesfully";
    case FBTestDaemonConnectionStateFinishedInError:
      return @"finished in error";
    default:
      return @"unknown";
  }
}

- (void)failWithError:(XCTestBootstrapError *)error
{
  [self.logger logFormat:@"Failing in state '%@' with error %@", [FBTestDaemonConnection stringForDaemonConnectionState:self.state], [error build]];
  self.state = FBTestDaemonConnectionStateFinishedInError;
  self.error = error;
}

@end

#pragma clang diagnostic pop
