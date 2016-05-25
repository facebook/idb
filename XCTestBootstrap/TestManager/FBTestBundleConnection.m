/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestBundleConnection.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

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

@interface FBTestBundleConnection () <XCTestManager_IDEInterface>

@property (atomic, assign, readwrite) FBTestBundleConnectionState state;
@property (atomic, strong, readwrite) XCTestBootstrapError *error;

@property (atomic, assign, readwrite) long long testBundleProtocolVersion;
@property (atomic, nullable, strong, readwrite) id<XCTestDriverInterface> testBundleProxy;
@property (atomic, nullable, strong, readwrite) DTXConnection *testBundleConnection;

@end

@implementation FBTestBundleConnection

+ (NSString *)clientProcessUniqueIdentifier
{
  static dispatch_once_t onceToken;
  static NSString *_clientProcessUniqueIdentifier;
  dispatch_once(&onceToken, ^{
    _clientProcessUniqueIdentifier = NSProcessInfo.processInfo.globallyUniqueString;
  });
  return _clientProcessUniqueIdentifier;
}

+ (instancetype)withDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface sessionIdentifier:(NSUUID *)sessionIdentifier queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDevice:device interface:interface sessionIdentifier:sessionIdentifier queue:queue logger:logger];
}

- (instancetype)initWithDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface sessionIdentifier:(NSUUID *)sessionIdentifier queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _interface = interface;
  _sessionIdentifier = sessionIdentifier;
  _queue = queue;
  _logger = logger;

  _state = FBTestBundleConnectionStateNotConnected;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Test Bundle Connection '%@'",
    [FBTestBundleConnection stateStringForState:self.state]
  ];
}

#pragma mark Message Forwarding

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
  NSAssert(NSThread.isMainThread, @"-[%@ %@] should be called from the main thread", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  if (self.state != FBTestBundleConnectionStateNotConnected) {
    return [[XCTestBootstrapError
      describeFormat:@"Cannot connect, state must be %@ but is %@", [FBTestBundleConnection stateStringForState:FBTestBundleConnectionStateNotConnected], [FBTestBundleConnection stateStringForState:self.state]]
      failBool:error];
  }

  [self connect];
  BOOL waitSuccess = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.state != FBTestBundleConnectionStateConnecting;
  }];

  if (!waitSuccess) {
    return [[[XCTestBootstrapError
      describe:@"Timeout establishing connection"]
      logger:self.logger]
      failBool:error];
  }
  if (self.state != FBTestBundleConnectionStateTestBundleReady) {
    return [[[[XCTestBootstrapError
      describeFormat:@"Error Establishing connection, current state '%@'", [FBTestBundleConnection stateStringForState:self.state]]
      logger:self.logger]
      causedBy:[self.error build]]
      failBool:error];
  }
  return YES;
}

- (BOOL)startTestPlanWithError:(NSError **)error
{
  if (self.state != FBTestBundleConnectionStateTestBundleReady) {
    return [[XCTestBootstrapError
      describeFormat:@"State should be '%@' got '%@", [FBTestBundleConnection stateStringForState:FBTestBundleConnectionStateTestBundleReady], [FBTestBundleConnection stateStringForState:self.state]]
      failBool:error];
  }

  [self.logger log:@"Bundle Connection scheduling start of Test Plan"];
  self.state = FBTestBundleConnectionStateAwaitingStartOfTestPlan;
  dispatch_async(self.queue, ^{
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
  });
  return YES;
}

- (void)disconnect
{
  [self.logger logFormat:@"Disconnecting Test Bundle in state '%@'", [FBTestBundleConnection stateStringForState:self.state]];

  if (self.state != FBTestBundleConnectionStateFinishedInError) {
    self.state = FBTestBundleConnectionStateFinishedSuccessfully;
  }
  [self.testBundleConnection suspend];
  [self.testBundleConnection cancel];
  self.testBundleConnection = nil;
  self.testBundleProxy = nil;
  self.testBundleProtocolVersion = 0;
}

#pragma mark Private

- (void)connect
{
  self.state = FBTestBundleConnectionStateConnecting;
  [self.logger log:@"Connecting Test Bundle"];
  dispatch_async(self.queue, ^{
    NSError *error;
    DTXTransport *transport = [self.device makeTransportForTestManagerService:&error];
    if (error || !transport) {
      [self failWithError:[[XCTestBootstrapError describe:@"Failed to create transport"] causedBy:error]];
      return;
    }

    DTXConnection *connection = [self setupTestBundleConnectionWithTransport:transport];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self sendStartSessionRequestToConnection:connection];
    });
  });
}

- (DTXConnection *)setupTestBundleConnectionWithTransport:(DTXTransport *)transport
{
  [self.logger logFormat:@"Creating the test bundle connection."];
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    FBTestBundleConnectionState state = self.state;
    [self.logger logFormat:@"Bundle Connection Disconnected in state '%@'", [FBTestBundleConnection stateStringForState:state]];
    if (state == FBTestBundleConnectionStateEndedTestPlan ||
        state == FBTestBundleConnectionStateFinishedSuccessfully ||
        state == FBTestBundleConnectionStateFinishedInError) {
      return;
    }
    [self failWithError:[[XCTestBootstrapError
        describeFormat:@"Lost connection to test process with state '%@'", [FBTestBundleConnection stateStringForState:state]]
        code:XCTestBootstrapErrorCodeLostConnection]];
  }];

  [self.logger logFormat:@"Listening for proxy connection request from the test bundle (all platforms)"];
  [connection
   handleProxyRequestForInterface:@protocol(XCTestManager_IDEInterface)
   peerInterface:@protocol(XCTestDriverInterface)
   handler:^(DTXProxyChannel *channel){
     [self.logger logFormat:@"Got proxy channel request from test bundle"];
     [channel setExportedObject:self queue:dispatch_get_main_queue()];
     id<XCTestDriverInterface> interface = channel.remoteObjectProxy;
     self.testBundleProxy = interface;
   }];
  [self.logger logFormat:@"Resuming the test bundle connection."];
  self.testBundleConnection = connection;
  [self.testBundleConnection resume];
  return self.testBundleConnection;
}

- (DTXRemoteInvocationReceipt *)sendStartSessionRequestToConnection:(DTXConnection *)connection
{
  [self.logger log:@"Checking test manager availability..."];
  DTXProxyChannel *proxyChannel = [self.testBundleConnection
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [proxyChannel setExportedObject:self queue:dispatch_get_main_queue()];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>) proxyChannel.remoteObjectProxy;

  NSString *bundlePath = NSBundle.mainBundle.bundlePath;
  if (![NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"app"]) {
    bundlePath = NSBundle.mainBundle.executablePath;
  }
  [self.logger logFormat:@"Starting test session with ID %@", self.sessionIdentifier.UUIDString];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_initiateSessionWithIdentifier:self.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:bundlePath
    protocolVersion:@(FBProtocolVersion)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    if (error || !version) {
      [self.logger logFormat:@"Client Daemon Interface failed, trying legacy format."];
      [self setupLegacyProtocolConnectionViaRemoteProxy:remoteProxy proxyChannel:proxyChannel bundlePath:bundlePath];
      return;
    }

    [self.logger logFormat:@"testmanagerd handled session request using protcol version %ld.", (long)FBProtocolVersion];
    [proxyChannel cancel];
  }];
  return receipt;
}

- (DTXRemoteInvocationReceipt *)setupLegacyProtocolConnectionViaRemoteProxy:(id<XCTestManager_DaemonConnectionInterface>)remoteProxy proxyChannel:(DTXProxyChannel *)proxyChannel bundlePath:(NSString *)bundlePath
{
  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_beginSessionWithIdentifier:self.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:bundlePath];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [self failWithError:[[XCTestBootstrapError describe:@"Client Daemon Interface failed"] causedBy:error]];
      return;
    }

    [self.logger logFormat:@"testmanagerd handled session request using legacy protocol."];
    [proxyChannel cancel];
  }];
  return receipt;
}

- (void)failWithError:(XCTestBootstrapError *)error
{
  [self.logger logFormat:@"Test Bundle Connection Failed with error %@", [error build]];
  self.error = error;
  self.state = FBTestBundleConnectionStateFinishedInError;
}

#pragma mark XCTestDriverInterface

- (id)_XCT_didBeginExecutingTestPlan
{
  if (self.state != FBTestBundleConnectionStateAwaitingStartOfTestPlan) {
    [self failWithError:[XCTestBootstrapError
      describeFormat:@"Test Plan Started, but state is %@", [FBTestBundleConnection stateStringForState:self.state]]];
    return nil;
  }
  [self.logger logFormat:@"Test Plan Started"];
  self.state = FBTestBundleConnectionStateRunningTestPlan;
  return [self.interface _XCT_didBeginExecutingTestPlan];
}

- (id)_XCT_didFinishExecutingTestPlan
{
  if (self.state != FBTestBundleConnectionStateRunningTestPlan) {
    [self failWithError:[XCTestBootstrapError
      describeFormat:@"Test Plan Ended, but state is %@", [FBTestBundleConnection stateStringForState:self.state]]];
    return nil;
  }
  [self.logger logFormat:@"Test Plan Ended"];
  self.state = FBTestBundleConnectionStateEndedTestPlan;;
  return [self.interface _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  self.testBundleProtocolVersion = protocolVersionInt;

  [self.logger logFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion];
  if (minimumVersionInt > FBProtocolVersion) {
    self.error = [[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]
      code:XCTestBootstrapErrorCodeStartupFailure];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    self.error = [[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt]
      code:XCTestBootstrapErrorCodeStartupFailure];
    return nil;
  }
  if (!self.device.requiresTestDaemonMediationForTestHostConnection) {
    self.error = [[XCTestBootstrapError
      describe:@"Test Bundle Connection cannot handle a Device that doesn't require daemon mediation"]
      code:XCTestBootstrapErrorCodeStartupFailure];
    return nil;
  }

  [self.logger logFormat:@"Test Bundle is Ready"];
  self.state = FBTestBundleConnectionStateTestBundleReady;
  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

+ (NSString *)stateStringForState:(FBTestBundleConnectionState)state
{
  switch (state) {
    case FBTestBundleConnectionStateNotConnected:
      return @"not connected";
    case FBTestBundleConnectionStateConnecting:
      return @"connecting";
    case FBTestBundleConnectionStateTestBundleReady:
      return @"bundle ready";
    case FBTestBundleConnectionStateAwaitingStartOfTestPlan:
      return @"awaiting start of test plan";
    case FBTestBundleConnectionStateRunningTestPlan:
      return @"running test plan";
    case FBTestBundleConnectionStateEndedTestPlan:
      return @"ended test plan";
    case FBTestBundleConnectionStateFinishedSuccessfully:
      return @"finished successfully";
    case FBTestBundleConnectionStateFinishedInError:
      return @"finished in error";
    default:
      return @"unknown";
  }
}

@end

#pragma clang diagnostic pop
