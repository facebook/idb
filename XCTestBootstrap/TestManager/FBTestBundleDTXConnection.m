/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestBundleDTXConnection.h"

#import <XCTestPrivate/XCTestDriverInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>

// Protocol for RPC with testmanagerd daemon
#import <XCTestPrivate/XCTMessagingChannel_DaemonToIDE-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_IDEToDaemon-Protocol.h>

// Protocol for RPC with XCTest runner (within the host app process)
#import <objc/runtime.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXSocketTransport.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <XCTestBootstrap/XCTestBootstrap-Swift.h>
#import <XCTestPrivate/DTXConnection-XCTestAdditions.h>
#import <XCTestPrivate/DTXProxyChannel-XCTestAdditions.h>
#import <XCTestPrivate/XCTMessagingChannel_IDEToRunner-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_RunnerToIDE-Protocol.h>

#import "FBTestConfiguration.h"
#import "XCTestBootstrapError.h"

static const NSInteger FBProtocolVersion = 36;
static const NSInteger FBProtocolMinimumVersion = 0x8;

static NSTimeInterval const BundleReadyTimeout = 60; // Time for `_XCT_testBundleReadyWithProtocolVersion` to be called after the 'connect'.
static NSTimeInterval const IDEInterfaceReadyTimeout = 60; // Time for `XCTestManager_IDEInterface` to be returned.
static NSTimeInterval const DaemonSessionReadyTimeout = 60; // Time for `_IDE_initiateSessionWithIdentifier` to be returned.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestBundleDTXConnection () <XCTestManager_IDEInterface, XCTMessagingChannel_DaemonToIDE, XCTMessagingChannel_RunnerToIDE>

@property (nonatomic, readonly, strong) FBTestManagerContext *context;
@property (nonatomic, readonly, strong) id<FBiOSTarget> target;
@property (nonatomic, readonly, assign) int testManagerdSocket;
@property (nonatomic, readonly, strong) id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject> interface;
@property (nonatomic, readonly, strong) dispatch_queue_t requestQueue;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *bundleDisconnected;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *bundleReadyFuture;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *testPlanFuture;

@property (nullable, nonatomic, strong) DTXConnection *testManagerdConnection;
@property (nullable, nonatomic, strong) id<XCTestDriverInterface> testBundleProxy;

@end

@implementation FBTestBundleDTXConnection

+ (NSString *)clientProcessUniqueIdentifier
{
  static dispatch_once_t onceToken;
  static NSString *_clientProcessUniqueIdentifier;
  dispatch_once(&onceToken, ^{
    _clientProcessUniqueIdentifier = NSProcessInfo.processInfo.globallyUniqueString;
  });
  return _clientProcessUniqueIdentifier;
}

+ (NSString *)clientProcessDisplayPath
{
  static dispatch_once_t onceToken;
  static NSString *_clientProcessDisplayPath;
  dispatch_once(&onceToken, ^{
    NSString *path = NSBundle.mainBundle.bundlePath;
    if (![path.pathExtension isEqualToString:@"app"]) {
      path = NSBundle.mainBundle.executablePath;
    }
    _clientProcessDisplayPath = path;
  });
  return _clientProcessDisplayPath;
}

- (instancetype)initWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target socket:(int)socket interface:(id)interface requestQueue:(dispatch_queue_t)requestQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _testManagerdSocket = socket;
  _interface = interface;
  _requestQueue = requestQueue;
  _logger = logger;

  _bundleDisconnected = FBMutableFuture.future;
  _bundleReadyFuture = FBMutableFuture.future;
  _testPlanFuture = FBMutableFuture.future;

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

#pragma mark Connection lifecycle

- (FBFutureContext<FBTestBundleDTXConnection *> *)connect
{
  int socket = self.testManagerdSocket;
  id<FBControlCoreLogger> logger = self.logger;
  [logger log:[NSString stringWithFormat:@"Wrapping testmanagerd socket (%d) in DTXTransport and DTXConnection", socket]];
  DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket
                                                                                   disconnectAction:^{
                                                                                     [logger log:@"Notified that daemon socket disconnected"];
                                                                                   }];
  DTXConnection *connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    [logger log:@"Notified that testmanagerd connection disconnected"];
    [self.bundleDisconnected resolveWithResult:NSNull.null];
  }];
  self.testManagerdConnection = connection;
  [logger log:[NSString stringWithFormat:@"testmanagerd socket %d wrapped in %@", socket, connection]];

  return [[FBFuture
           futureWithResult:self]
          onQueue:self.requestQueue
          contextualTeardown:^(id _, FBFutureState __) {
            [logger log:[NSString stringWithFormat:@"Ending the testmanagerd connection. %@", connection]];
            [connection suspend];
            [connection cancel];
            return FBFuture.empty;
          }];
}

- (FBFuture<NSNull *> *)setupAndStartSession
{
  DTXConnection *connection = self.testManagerdConnection;
  return [[FBFuture
           futureWithFutures:@[
             [self setupTestBundleConnectionWithConnection:connection],
             [self sendStartSessionRequestWithConnection:connection],
           ]]
          onQueue:self.requestQueue
          fmap:^FBFuture *(NSArray<id> *results) {
            self.testBundleProxy = results[0];
            return FBFuture.empty;
          }];
}

- (FBFuture<NSNull *> *)waitForBundleReady
{
  [self.logger log:@"Waiting for test bundle to be ready.."];
  return [self.bundleReadyFuture timeout:BundleReadyTimeout waitingFor:@"Bundle Ready to be called"];
}

- (void)startExecutingTestPlan
{
  [self.logger log:[NSString stringWithFormat:@"Starting Execution of the test plan w/ version %ld", FBProtocolVersion]];
  [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
}

- (FBFuture<NSNull *> *)waitForBundleDisconnected
{
  return self.bundleDisconnected;
}

- (BOOL)testPlanCompleted
{
  return self.testPlanFuture.hasCompleted;
}

- (FBFuture<id<XCTestDriverInterface>> *)setupTestBundleConnectionWithConnection:(DTXConnection *)connection
{
  FBMutableFuture<id<XCTestDriverInterface>> *future = FBMutableFuture.future;
  [self.logger log:@"Listening for proxy connection request from the test bundle (all platforms)"];

  [connection
   xct_handleProxyRequestForInterface:@protocol(XCTMessagingChannel_RunnerToIDE)
   peerInterface:@protocol(XCTMessagingChannel_IDEToRunner)
   handler:^(DTXProxyChannel *channel) {
     [self.logger log:@"Got proxy channel request from test bundle"];
     [channel setExportedObject:self queue:self.target.workQueue];
     id<XCTestDriverInterface> interface = channel.remoteObjectProxy;
     [future resolveWithResult:interface];
   }];
  [self.logger log:@"Resuming the test bundle connection."];
  [connection resume];

  return [future timeout:IDEInterfaceReadyTimeout waitingFor:@"XCTestManager_IDEInterface to be ready"];
}

- (FBFuture<NSNumber *> *)sendStartSessionRequestWithConnection:(DTXConnection *)connection
{
  [self.logger log:@"Checking test manager availability..."];
  DTXProxyChannel *proxyChannel = [connection
                                   xct_makeProxyChannelWithRemoteInterface:@protocol(XCTMessagingChannel_IDEToDaemon)
                                   exportedInterface:@protocol(XCTMessagingChannel_DaemonToIDE)];
  [proxyChannel xct_setAllowedClassesForTestingProtocols];
  [proxyChannel setExportedObject:self queue:self.target.workQueue];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>) proxyChannel.remoteObjectProxy;

  [self.logger log:[NSString stringWithFormat:@"Starting test session with ID %@", self.context.sessionIdentifier.UUIDString]];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
                                         _IDE_initiateSessionWithIdentifier:self.context.sessionIdentifier
                                         forClient:self.class.clientProcessUniqueIdentifier
                                         atPath:self.class.clientProcessDisplayPath
                                         protocolVersion:@(FBProtocolVersion)];

  NSString *sessionStartMethod = NSStringFromSelector(@selector(_IDE_initiateSessionWithIdentifier:forClient:atPath:protocolVersion:));

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    [proxyChannel cancel];
    if (error) {
      [self.logger log:[NSString stringWithFormat:@"testmanagerd did %@ failed: %@", sessionStartMethod, error]];
      [future resolveWithError:error];
      return;
    }
    [self.logger log:[NSString stringWithFormat:@"testmanagerd handled session request using protocol version requested=%ld received=%ld", FBProtocolVersion, version.longValue]];
    [future resolveWithResult:version];
  }];

  return [future timeout:DaemonSessionReadyTimeout waitingFor:[NSString stringWithFormat:@"%@ to be resolved", sessionStartMethod]];
}

- (void)concludeWithError:(NSError *)error
{
  [self.logger log:[NSString stringWithFormat:@"Test Completed with error: %@", error]];
  [self.bundleReadyFuture resolveWithError:error];
  [self.testPlanFuture resolveWithError:error];
}

#pragma mark XCTestDriverInterface

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.testPlanFuture resolveWithResult:NSNull.null];
  return [self.interface _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  [self.logger log:[NSString stringWithFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion]];
  if (minimumVersionInt > FBProtocolVersion) {
    NSError *error = [[[XCTestBootstrapError
                        describe:[NSString stringWithFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]]
                       code:XCTestBootstrapErrorCodeStartupFailure]
                      build];
    [self concludeWithError:error];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    NSError *error = [[[XCTestBootstrapError
                        describe:[NSString stringWithFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion, protocolVersionInt]]
                       code:XCTestBootstrapErrorCodeStartupFailure]
                      build];
    [self concludeWithError:error];
    return nil;
  }
  [self.logger log:@"Test Bundle is Ready"];
  [self.bundleReadyFuture resolveWithResult:NSNull.null];
  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

- (id)_XCT_initializationForUITestingDidFailWithError:(NSError *)error
{
  NSError *innerError = [[[[XCTestBootstrapError
                            describe:@"Failed to initialize for UI testing"]
                           causedBy:error]
                          code:XCTestBootstrapErrorCodeStartupFailure]
                         build];
  [self concludeWithError:innerError];
  return nil;
}

/// Method called to notify us (the "IDE") that XCTest "runner" has been
/// loaded into the host app process and is ready.
///
/// Return value must be an XCTestConfiguration object that specifies which
/// tests should run alongside other options for the test execution.
- (id)_XCT_testRunnerReadyWithCapabilities:(XCTCapabilities *)arg1
{
  [self.logger log:@"Test Bundle is Ready"];

  DTXRemoteInvocationReceipt *receipt = [[objc_lookUpClass("DTXRemoteInvocationReceipt") alloc] init];
  [receipt invokeCompletionWithReturnValue:self.context.testConfiguration.xcTestConfiguration error:nil];

  [self.bundleReadyFuture resolveWithResult:NSNull.null];
  return receipt;
}

@end

#pragma clang diagnostic pop
