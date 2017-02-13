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

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerAPIMediator.h"
#import "FBDeviceOperator.h"
#import "FBTestManagerContext.h"
#import "FBTestDaemonResult.h"

/**
 An Enumeration of Mutually-Exclusive Test Daemon States.
 */
typedef NS_ENUM(NSUInteger, FBTestDaemonConnectionState) {
  FBTestDaemonConnectionStateNotConnected = 0,
  FBTestDaemonConnectionStateConnecting = 1,
  FBTestDaemonConnectionStateReadyToExecuteTestPlan = 2,
  FBTestDaemonConnectionStateRunningTestPlan = 3,
  FBTestDaemonConnectionStateEndedTestPlan = 4,
  FBTestDaemonConnectionStateResultAvailable = 5,
};

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestDaemonConnection () <XCTestManager_IDEInterface>

@property (nonatomic, weak, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBDeviceOperator> deviceOperator;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@property (atomic, assign, readwrite) FBTestDaemonConnectionState state;
@property (atomic, assign, readwrite) long long daemonProtocolVersion;
@property (atomic, nullable, strong, readwrite) FBTestDaemonResult *result;
@property (atomic, nullable, strong, readwrite) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (atomic, nullable, strong, readwrite) DTXConnection *daemonConnection;

@end

@implementation FBTestDaemonConnection

#pragma mark Initializers

+ (instancetype)connectionWithContext:(FBTestManagerContext *)context deviceOperator:(id<FBDeviceOperator>)deviceOperator interface:(id<XCTestManager_IDEInterface, NSObject>)interface queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithWithContext:context deviceOperator:deviceOperator interface:interface queue:queue logger:logger];
}

- (instancetype)initWithWithContext:(FBTestManagerContext *)context deviceOperator:(id<FBDeviceOperator>)deviceOperator interface:(id<XCTestManager_IDEInterface, NSObject>)interface queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _deviceOperator = deviceOperator;
  _interface = interface;
  _queue = queue;
  _logger = [logger withPrefix:[NSString stringWithFormat:@"%@:", deviceOperator.udid]];

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

- (nullable FBTestDaemonResult *)connectWithTimeout:(NSTimeInterval)timeout
{
  if (self.result) {
    return self.result;
  }
  if (self.state != FBTestDaemonConnectionStateNotConnected) {
    XCTestBootstrapError *error = [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateNotConnected], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }

  [self connect];
  BOOL waitSuccess = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.state != FBTestDaemonConnectionStateConnecting;
  }];

  if (!waitSuccess) {
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describeFormat:@"Timed out %f seconds waiting for daemon connection", timeout]
      code:XCTestBootstrapErrorCodeStartupTimeout];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }
  if (self.state != FBTestDaemonConnectionStateReadyToExecuteTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Daemon not in expected state '%@', was in state '%@'", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateReadyToExecuteTestPlan], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }
  return nil;
}

- (nullable FBTestDaemonResult *)notifyTestPlanStarted
{
  if (self.state != FBTestDaemonConnectionStateReadyToExecuteTestPlan) {
    XCTestBootstrapError *error =  [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateReadyToExecuteTestPlan], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }

  [self.logger log:@"Daemon Notified of start of test plan"];
  self.state = FBTestDaemonConnectionStateRunningTestPlan;
  return nil;
}

- (nullable FBTestDaemonResult *)notifyTestPlanEnded
{
  if (self.state != FBTestDaemonConnectionStateRunningTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", [FBTestDaemonConnection stringForDaemonConnectionState:FBTestDaemonConnectionStateRunningTestPlan], [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }

  [self.logger log:@"Daemon Notified of end of test plan"];
  self.state = FBTestDaemonConnectionStateEndedTestPlan;
  return nil;
}

- (nullable FBTestDaemonResult *)checkForResult
{
  return self.result;
}

- (FBTestDaemonResult *)disconnect
{
  [self.logger logFormat:@"Disconnecting Daemon from state '%@'", [FBTestDaemonConnection stringForDaemonConnectionState:self.state]];

  FBTestDaemonResult *result = nil;
  if (self.state == FBTestDaemonConnectionStateEndedTestPlan) {
    result = [self concludeWithResult:FBTestDaemonResult.success];
  } else {
    result = [self concludeWithResult:FBTestDaemonResult.clientRequestedDisconnect];
  }

  [self.daemonConnection suspend];
  [self.daemonConnection cancel];
  self.daemonConnection = nil;
  self.daemonProxy = nil;
  self.daemonProtocolVersion = 0;

  return result;
}

#pragma mark Private

- (void)connect
{
  self.state = FBTestDaemonConnectionStateConnecting;
  [self.logger log:@"Starting the daemon connection"];
  dispatch_async(self.queue, ^{
    NSError *innerError = nil;
    DTXTransport *transport = [self.deviceOperator makeTransportForTestManagerServiceWithLogger:self.logger error:&innerError];
    if (innerError || !transport) {
      XCTestBootstrapError *error = [[XCTestBootstrapError
        describe:@"Failed to created secondary test manager transport"]
        causedBy:innerError];
      [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
    }
    [self createDaemonConnectionWithTransport:transport];
  });
}

- (DTXConnection *)createDaemonConnectionWithTransport:(DTXTransport *)transport
{
  DTXConnection *connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    [self daemonDisconnectedWithState:self.state];
  }];
  [self.logger logFormat:@"Resuming the daemon connection."];
  self.daemonConnection = connection;

  [connection resume];
  DTXProxyChannel *channel = [connection
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [channel setExportedObject:self queue:dispatch_get_main_queue()];
  self.daemonProxy = (id<XCTestManager_DaemonConnectionInterface>)channel.remoteObjectProxy;

  [self.logger logFormat:@"Whitelisting test process ID %d", self.context.testRunnerPID];
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.context.testRunnerPID) protocolVersion:@(FBProtocolVersion)];
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

- (FBTestDaemonResult *)daemonDisconnectedWithState:(FBTestDaemonConnectionState)state
{
  [self.logger logFormat:@"Notified that daemon disconnected from state '%@'", [FBTestDaemonConnection stringForDaemonConnectionState:state]];
  if (self.result) {
    return self.result;
  }
  if (state != FBTestDaemonConnectionStateEndedTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Disconnected with state %@", [FBTestDaemonConnection stringForDaemonConnectionState:state]];
    return [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
  }
  return [self concludeWithResult:FBTestDaemonResult.success];
}

- (DTXRemoteInvocationReceipt *)setupDaemonConnectionViaLegacyProtocol
{
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.context.testRunnerPID)];
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
    case FBTestDaemonConnectionStateResultAvailable:
      return @"result available";
    default:
      return @"unknown";
  }
}

- (FBTestDaemonResult *)concludeWithResult:(FBTestDaemonResult *)result
{
  if (self.result) {
    return self.result;
  }
  [self.logger logFormat:@"Daemon Connection Ended with result: %@", result];
  self.result = result;
  self.state = FBTestDaemonConnectionStateResultAvailable;
  return result;
}

@end

#pragma clang diagnostic pop
