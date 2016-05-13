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

@property (nonatomic, assign, readwrite) long long testBundleProtocolVersion;
@property (nonatomic, nullable, strong, readwrite) id<XCTestDriverInterface> testBundleProxy;
@property (nonatomic, nullable, strong, readwrite) DTXConnection *testBundleConnection;

@property (nonatomic, strong, readwrite) NSError *protocolError;
@property (nonatomic, assign, readwrite) BOOL testPlanRunning;

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

  return self;
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

  dispatch_group_t group = dispatch_group_create();
  __block BOOL success = NO;
  __block NSError *innerError = nil;
  [self connectWithGroup:group completion:^(BOOL startupSuccess, NSError *startupError) {
    innerError = startupError;
    success = startupSuccess;
  }];

  if (![NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout notifiedBy:group onQueue:self.queue]) {
    return [[[XCTestBootstrapError
      describeFormat:@"Timed out waiting for connection"]
      logger:self.logger]
      failBool:error];
  }
  if (!success) {
    return [[[[XCTestBootstrapError
      describe:@"Failed to connect test runner"]
      causedBy:innerError]
      logger:self.logger]
      failBool:error];
  }
  return YES;
}

- (void)disconnect
{
  [self.testBundleConnection suspend];
  [self.testBundleConnection cancel];
  self.testBundleConnection = nil;
  self.testBundleProxy = nil;
  self.testBundleProtocolVersion = 0;
  self.testPlanRunning = NO;
}

#pragma mark Private

- (void)connectWithGroup:(dispatch_group_t)group completion:(void (^)(BOOL, NSError *))completion
{
  dispatch_group_async(group, self.queue, ^{
    NSError *error;
    DTXTransport *transport = [self.device makeTransportForTestManagerService:&error];
    if (error || !transport) {
      completion(NO, error);
    }

    [self setupTestBundleConnectionWithTransport:transport group:group completion:^(id<XCTestDriverInterface> interface, NSError *bundleConnectionError) {
      if (!interface) {
        completion(NO, [[[XCTestBootstrapError describe:@"Test Bundle connection failed, session was not started"] causedBy:bundleConnectionError] build]);
        return;
      }
      completion(YES, nil);
    }];
    dispatch_group_async(group, dispatch_get_main_queue(), ^{
      [self sendStartSessionRequestToTestManagerWithGroup:group completion:^(DTXProxyChannel *channel, NSError *sessionRequestError) {
        if (!channel) {
          [self.logger logFormat:@"Failed to start session with error %@", sessionRequestError];
        }
      }];
    });
  });
}

- (void)setupTestBundleConnectionWithTransport:(DTXTransport *)transport group:(dispatch_group_t)group completion:(void(^)( id<XCTestDriverInterface>, NSError *))completion
{
  [self.logger logFormat:@"Creating the connection."];
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];

  [connection registerDisconnectHandler:^{
    if (self.testPlanRunning) {
      completion(nil, [[[XCTestBootstrapError describe:@"Lost connection to test process"] code:XCTestBootstrapErrorCodeLostConnection] build]);
    }
  }];
  [self.logger logFormat:@"Listening for proxy connection request from the test bundle (all platforms)"];

  dispatch_group_enter(group);
  [connection
   handleProxyRequestForInterface:@protocol(XCTestManager_IDEInterface)
   peerInterface:@protocol(XCTestDriverInterface)
   handler:^(DTXProxyChannel *channel){
     [self.logger logFormat:@"Got proxy channel request from test bundle"];
     [channel setExportedObject:self queue:dispatch_get_main_queue()];
     id<XCTestDriverInterface> interface = channel.remoteObjectProxy;
     self.testBundleProxy = interface;
     completion(interface, nil);
     dispatch_group_leave(group);
   }];
  self.testBundleConnection = connection;
  [self.logger logFormat:@"Resuming the connection."];
  [self.testBundleConnection resume];
}

- (void)sendStartSessionRequestToTestManagerWithGroup:(dispatch_group_t)group completion:(void(^)(DTXProxyChannel *, NSError *))completion
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
  [self.logger logFormat:@"Starting test session with ID %@", self.sessionIdentifier];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_initiateSessionWithIdentifier:self.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:bundlePath
    protocolVersion:@(FBProtocolVersion)];

  dispatch_group_enter(group);
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    if (error || !version) {
      completion(nil, [[[XCTestBootstrapError describe:@"Client Daemon Interface failed"] causedBy:error] build]);
      return;
    }

    [self.logger logFormat:@"testmanagerd handled session request."];
    [proxyChannel cancel];
    dispatch_group_leave(group);
  }];
}

#pragma mark XCTestDriverInterface

- (id)_XCT_didBeginExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Started"];
  self.testPlanRunning = YES;
  return [self.interface _XCT_didBeginExecutingTestPlan];
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Ended"];
  self.testPlanRunning = NO;
  return [self.interface _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  self.testBundleProtocolVersion = protocolVersionInt;

  [self.logger logFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion];
  if (minimumVersionInt > FBProtocolVersion) {
    self.protocolError = [[[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]
      code:XCTestBootstrapErrorCodeStartupFailure]
      build];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    self.protocolError = [[[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt]
      code:XCTestBootstrapErrorCodeStartupFailure]
      build];
    return nil;
  }
  if (!self.device.requiresTestDaemonMediationForTestHostConnection) {
    self.protocolError = [[[XCTestBootstrapError
      describe:@"Test Bundle Connection cannot handle a Device that doesn't require daemon mediation"]
      code:XCTestBootstrapErrorCodeStartupFailure]
      build];
    return nil;
  }

  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

@end

#pragma clang diagnostic pop
