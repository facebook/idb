/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerContext.h"
#import "FBTestDaemonResult.h"

typedef NSString *FBTestDaemonConnectionState NS_STRING_ENUM;
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateNotConnected = @"not connected";
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateConnecting = @"connecting";
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateReadyToExecuteTestPlan = @"ready to execute test plan";
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateExecutingTestPlan = @"executing test plan";
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateEndedTestPlan = @"ended test plan";
static FBTestDaemonConnectionState const FBTestDaemonConnectionStateResultAvailable = @"result available";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestDaemonConnection () <XCTestManager_IDEInterface>

@property (nonatomic, strong, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@property (atomic, strong, readwrite) FBTestDaemonConnectionState state;
@property (atomic, assign, readwrite) long long daemonProtocolVersion;
@property (atomic, nullable, strong, readwrite) FBTestDaemonResult *result;
@property (atomic, nullable, strong, readwrite) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (atomic, nullable, strong, readwrite) DTXConnection *daemonConnection;

@property (nonatomic, strong, readonly) FBMutableFuture<FBTestDaemonResult *> *connectFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<FBTestDaemonResult *> *resultFuture;

@end

@implementation FBTestDaemonConnection

#pragma mark Initializers

+ (instancetype)connectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithWithContext:context target:target interface:interface requestQueue:requestQueue logger:logger];
}

- (instancetype)initWithWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _interface = interface;
  _requestQueue = requestQueue;
  _logger = logger;

  _state = FBTestDaemonConnectionStateNotConnected;

  _connectFuture = FBMutableFuture.new;
  _resultFuture = FBMutableFuture.new;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Test Daemon Connection %@", self.state];
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

- (FBFuture<FBTestDaemonResult *> *)connect
{
  if (self.state != FBTestDaemonConnectionStateNotConnected) {
    XCTestBootstrapError *error = [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", FBTestDaemonConnectionStateNotConnected, self.state];
    [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
    return self.connectFuture;
  }
  [self doConnect];
  return self.connectFuture;
}

- (FBFuture<FBTestDaemonResult *> *)notifyTestPlanStarted
{
  if (self.state != FBTestDaemonConnectionStateReadyToExecuteTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", FBTestDaemonConnectionStateReadyToExecuteTestPlan, self.state];
    return [FBFuture futureWithResult:[self concludeWithResult:[FBTestDaemonResult failedInError:error]]];
  }

  [self.logger log:@"Daemon Notified of start of test plan"];
  self.state = FBTestDaemonConnectionStateExecutingTestPlan;
  return [FBFuture futureWithResult:FBTestDaemonResult.success];
}

- (FBFuture<FBTestDaemonResult *> *)notifyTestPlanEnded
{
  if (self.state != FBTestDaemonConnectionStateExecutingTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError describeFormat:@"State should be '%@' got '%@", FBTestDaemonConnectionStateExecutingTestPlan, self.state];
    return [FBFuture futureWithResult:[self concludeWithResult:[FBTestDaemonResult failedInError:error]]];
  }

  [self.logger log:@"Daemon Notified of end of test plan"];
  self.state = FBTestDaemonConnectionStateEndedTestPlan;
  return [FBFuture futureWithResult:FBTestDaemonResult.success];
}

- (FBFuture<FBTestDaemonResult *> *)completed
{
  return self.resultFuture;
}

- (FBTestDaemonResult *)disconnect
{
  [self.logger logFormat:@"Disconnecting Daemon from state '%@'", self.state];

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

- (void)doConnect
{
  self.state = FBTestDaemonConnectionStateConnecting;
  [self.logger log:@"Starting the daemon connection"];

  [[[self.target
    transportForTestManagerService]
    onQueue:self.requestQueue enter:^(NSNumber *socket, FBMutableFuture<NSNull *> *teardown){
      DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket.intValue disconnectAction:^{
        [teardown resolveWithResult:NSNull.null];
      }];
      return [self createDaemonConnectionWithTransport:transport];
    }]
    onQueue:self.target.workQueue handleError:^(NSError *innerError) {
      XCTestBootstrapError *error = [[XCTestBootstrapError
        describe:@"Failed to created secondary test manager transport"]
        causedBy:innerError];
      [self concludeWithResult:[FBTestDaemonResult failedInError:error]];
      return [FBFuture futureWithError:error.build];
    }];
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
  [channel setExportedObject:self queue:self.target.workQueue];
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
    [self.connectFuture resolveWithResult:FBTestDaemonResult.success];
  }];
  return connection;
}

- (FBTestDaemonResult *)daemonDisconnectedWithState:(FBTestDaemonConnectionState)state
{
  [self.logger logFormat:@"Notified that daemon disconnected from state '%@'", state];
  if (self.result) {
    return self.result;
  }
  if (state != FBTestDaemonConnectionStateEndedTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Disconnected with state %@", state];
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

- (FBTestDaemonResult *)concludeWithResult:(FBTestDaemonResult *)result
{
  if (self.result) {
    return self.result;
  }
  [self.logger logFormat:@"Daemon Connection Ended with result: %@", result];
  self.result = result;
  self.state = FBTestDaemonConnectionStateResultAvailable;
  NSError *error = result.error;
  if (error) {
    [self.resultFuture resolveWithError:error];
    [self.connectFuture resolveWithError:error];
  } else {
    [self.resultFuture resolveWithResult:result];
    [self.connectFuture resolveWithResult:result];
  }

  return result;
}

@end

#pragma clang diagnostic pop
