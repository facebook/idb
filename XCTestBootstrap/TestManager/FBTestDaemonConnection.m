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

#import "XCTestBootstrapError.h"
#import "FBTestManagerAPIMediator.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestDaemonConnection () <XCTestManager_IDEInterface>

@property (nonatomic, assign, readwrite) long long daemonProtocolVersion;
@property (nonatomic, nullable, strong, readwrite) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (nonatomic, nullable, strong, readwrite) DTXConnection *daemonConnection;

@end

@implementation FBTestDaemonConnection

#pragma mark Initializers

+ (instancetype)withTransport:(DTXTransport *)transport interface:(id<XCTestManager_IDEInterface, NSObject>)interface testBundleProxy:(id<XCTestDriverInterface>)testBundleProxy testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithTransport:transport interface:interface testBundleProxy:testBundleProxy testRunnerPID:testRunnerPID queue:queue logger:logger];
}

- (instancetype)initWithTransport:(DTXTransport *)transport interface:(id<XCTestManager_IDEInterface, NSObject>)interface testBundleProxy:(id<XCTestDriverInterface>)testBundleProxy testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _transport = transport;
  _interface = interface;
  _testBundleProxy = testBundleProxy;
  _queue = queue;
  _testRunnerPID = testRunnerPID;
  _logger = logger;

  return self;
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
  dispatch_group_t group = dispatch_group_create();
  __block BOOL success = NO;
  __block NSError *innerError = nil;
  [self setupDaemonConnectionWithGroup:group completion:^(BOOL connectionSuccess, NSError *connectionError) {
    success = connectionSuccess;
    innerError = connectionError;
  }];
  if (![NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout notifiedBy:group onQueue:self.queue]) {
    return [[XCTestBootstrapError
      describeFormat:@"Timed out waiting for daemon connection"]
      failBool:error];
  }
  if (!success) {
    return [[[XCTestBootstrapError
      describe:@"Failed to connect daemon connection"]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

- (void)disconnect
{
  [self.daemonConnection suspend];
  [self.daemonConnection cancel];
  self.daemonConnection = nil;
  self.daemonProxy = nil;
  self.daemonProtocolVersion = 0;
}

#pragma mark Private

- (void)setupDaemonConnectionWithGroup:(dispatch_group_t)group completion:(void (^)(BOOL, NSError *))completion
{
  DTXTransport *transport = self.transport;
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    completion(NO, [[[XCTestBootstrapError describe:@"Lost connection to test manager service."] code:XCTestBootstrapErrorCodeLostConnection] build]);
  }];
  [self.logger logFormat:@"Resuming the secondary connection."];
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
      [self setupDaemonConnectionViaLegacyProtocolWithCompletion:completion];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self.logger logFormat:@"Got whitelisting response and daemon protocol version %lld", self.daemonProtocolVersion];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:version];
    completion(YES, nil);
  }];
}

- (void)setupDaemonConnectionViaLegacyProtocolWithCompletion:(void (^)(BOOL, NSError *))completion
{
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [self.logger logFormat:@"Error in whitelisting response from testmanagerd: %@ (%@), ignoring for now.", error.localizedDescription, error.localizedRecoverySuggestion];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self.logger logFormat:@"Got legacy whitelisting response, daemon protocol version is 14"];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
  }];
}

@end

#pragma clang diagnostic pop
