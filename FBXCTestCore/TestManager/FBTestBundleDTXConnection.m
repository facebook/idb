/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestBundleDTXConnection.h"

#import <objc/runtime.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXSocketTransport.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <FBControlCore/FBControlCore.h>
#import <FBXCTestCore/FBXCTestCore-Swift.h>
#import <XCTestPrivate/DTXConnection-XCTestAdditions.h>
#import <XCTestPrivate/DTXProxyChannel-XCTestAdditions.h>
#import <XCTestPrivate/XCTMessagingChannel_DaemonToIDE-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_IDEToDaemon-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_IDEToRunner-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_RunnerToIDE-Protocol.h>
#import <XCTestPrivate/XCTestDriverInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>

#import "FBTestConfiguration.h"

static const NSInteger FBProtocolVersion = 36;
static const NSInteger FBProtocolMinimumVersion = 0x8;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestBundleDTXConnection () <XCTestManager_IDEInterface, XCTMessagingChannel_DaemonToIDE, XCTMessagingChannel_RunnerToIDE>

@property (nonatomic, readonly, strong) TestManagerContext *context;
@property (nonatomic, readonly, strong) dispatch_queue_t workQueue;
@property (nonatomic, readonly, assign) int testManagerdSocket;
@property (nonatomic, readonly, strong) id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject> interface;
@property (nonatomic, readonly, strong) id<FBTestBundleDTXConnectionDelegate> delegate;
@property (nonatomic, readonly, strong) dispatch_queue_t requestQueue;
@property (nonatomic, readonly, strong) id<TestManagerLogSink> logger;

@property (nullable, nonatomic, strong) DTXConnection *testManagerdConnection;
// Set from the proxy handler's queue and read once the delegate has been told the bundle is ready.
@property (nullable, atomic, strong) id<XCTestDriverInterface> testBundleProxy;

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

- (instancetype)initWithContext:(TestManagerContext *)context workQueue:(dispatch_queue_t)workQueue socket:(int)socket interface:(id)interface delegate:(id<FBTestBundleDTXConnectionDelegate>)delegate requestQueue:(dispatch_queue_t)requestQueue logger:(id<TestManagerLogSink>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _workQueue = workQueue;
  _testManagerdSocket = socket;
  _interface = interface;
  _delegate = delegate;
  _requestQueue = requestQueue;
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

#pragma mark Connection lifecycle

- (BOOL)connectWithError:(NSError **)error
{
  int socket = self.testManagerdSocket;
  id<TestManagerLogSink> logger = self.logger;
  [logger log:[NSString stringWithFormat:@"Wrapping testmanagerd socket (%d) in DTXTransport and DTXConnection", socket]];
  DTXConnection *connection;
  // DTX asserts internally on a dead socket; the raise would otherwise cross
  // Swift frames, where it cannot be caught, and abort the process.
  @try {
    DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket
                                                                                     disconnectAction:^{
                                                                                       [logger log:@"Notified that daemon socket disconnected"];
                                                                                     }];
    connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  } @catch (NSException *exception) {
    if (error) {
      *error = [XCTestBootstrapErrors testFailure:[NSString stringWithFormat:@"Failed to wrap testmanagerd socket %d in DTXConnection: %@", socket, exception]];
    }
    return NO;
  }
  [connection registerDisconnectHandler:^{
    [logger log:@"Notified that testmanagerd connection disconnected"];
    [self.delegate testBundleConnectionDidDisconnect];
  }];
  self.testManagerdConnection = connection;
  [logger log:[NSString stringWithFormat:@"testmanagerd socket %d wrapped in %@", socket, connection]];
  return YES;
}

- (void)disconnect
{
  DTXConnection *connection = self.testManagerdConnection;
  if (!connection) {
    return;
  }
  // Synchronous so the connection is down by the time the caller's scope has exited, matching the
  // awaited teardown this replaces.
  dispatch_sync(self.requestQueue, ^{
    [self.logger log:[NSString stringWithFormat:@"Ending the testmanagerd connection. %@", connection]];
    [connection suspend];
    [connection cancel];
  });
}

- (void)setupAndStartSession
{
  DTXConnection *connection = self.testManagerdConnection;
  [self setupTestBundleConnectionWithConnection:connection];
  [self sendStartSessionRequestWithConnection:connection];
}

- (void)startExecutingTestPlan
{
  [self.logger log:[NSString stringWithFormat:@"Starting Execution of the test plan w/ version %ld", FBProtocolVersion]];
  [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
}

- (void)setupTestBundleConnectionWithConnection:(DTXConnection *)connection
{
  [self.logger log:@"Listening for proxy connection request from the test bundle (all platforms)"];

  [connection
   xct_handleProxyRequestForInterface:@protocol(XCTMessagingChannel_RunnerToIDE)
   peerInterface:@protocol(XCTMessagingChannel_IDEToRunner)
   handler:^(DTXProxyChannel *channel) {
     [self.logger log:@"Got proxy channel request from test bundle"];
     [channel setExportedObject:self queue:self.workQueue];
     self.testBundleProxy = channel.remoteObjectProxy;
     [self.delegate testBundleConnectionDidOpenProxyChannel];
   }];
  [self.logger log:@"Resuming the test bundle connection."];
  [connection resume];
}

- (void)sendStartSessionRequestWithConnection:(DTXConnection *)connection
{
  [self.logger log:@"Checking test manager availability..."];
  DTXProxyChannel *proxyChannel = [connection
                                   xct_makeProxyChannelWithRemoteInterface:@protocol(XCTMessagingChannel_IDEToDaemon)
                                   exportedInterface:@protocol(XCTMessagingChannel_DaemonToIDE)];
  [proxyChannel xct_setAllowedClassesForTestingProtocols];
  [proxyChannel setExportedObject:self queue:self.workQueue];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>) proxyChannel.remoteObjectProxy;

  [self.logger log:[NSString stringWithFormat:@"Starting test session with ID %@", self.context.sessionIdentifier.UUIDString]];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
                                         _IDE_initiateSessionWithIdentifier:self.context.sessionIdentifier
                                         forClient:self.class.clientProcessUniqueIdentifier
                                         atPath:self.class.clientProcessDisplayPath
                                         protocolVersion:@(FBProtocolVersion)];

  NSString *sessionStartMethod = NSStringFromSelector(@selector(_IDE_initiateSessionWithIdentifier:forClient:atPath:protocolVersion:));

  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    [proxyChannel cancel];
    if (error) {
      [self.logger log:[NSString stringWithFormat:@"testmanagerd did %@ failed: %@", sessionStartMethod, error]];
      [self.delegate testBundleConnectionDidStartSessionWithError:error];
      return;
    }
    [self.logger log:[NSString stringWithFormat:@"testmanagerd handled session request using protocol version requested=%ld received=%ld", FBProtocolVersion, version.longValue]];
    [self.delegate testBundleConnectionDidStartSessionWithError:nil];
  }];
}

- (void)concludeWithError:(NSError *)error
{
  [self.logger log:[NSString stringWithFormat:@"Test Completed with error: %@", error]];
  [self.delegate testBundleConnectionBundleDidFailWithError:error];
}

#pragma mark XCTestDriverInterface

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.delegate testBundleConnectionDidFinishTestPlan];
  return [self.interface _XCT_didFinishExecutingTestPlan];
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  [self.logger log:[NSString stringWithFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion]];
  if (minimumVersionInt > FBProtocolVersion) {
    NSError *error = [XCTestBootstrapErrors startupFailure:[NSString stringWithFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]
                                           underlyingError:nil];
    [self concludeWithError:error];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    NSError *error = [XCTestBootstrapErrors startupFailure:[NSString stringWithFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion, protocolVersionInt]
                                           underlyingError:nil];
    [self concludeWithError:error];
    return nil;
  }
  [self.logger log:@"Test Bundle is Ready"];
  [self.delegate testBundleConnectionBundleDidBecomeReady];
  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

- (id)_XCT_initializationForUITestingDidFailWithError:(NSError *)error
{
  NSError *innerError = [XCTestBootstrapErrors startupFailure:@"Failed to initialize for UI testing" underlyingError:error];
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

  [self.delegate testBundleConnectionBundleDidBecomeReady];
  return receipt;
}

@end

#pragma clang diagnostic pop
