/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestBundleConnection.h"

#import <XCTestPrivate/XCTestDriverInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>

// Protocol for RPC with testmanagerd daemon
#import <XCTestPrivate/XCTMessagingChannel_IDEToDaemon-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_DaemonToIDE-Protocol.h>

// Protocol for RPC with XCTest runner (within the host app process)
#import <XCTestPrivate/XCTMessagingChannel_RunnerToIDE-Protocol.h>
#import <XCTestPrivate/XCTMessagingChannel_IDEToRunner-Protocol.h>


#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <XCTestPrivate/DTXConnection-XCTestAdditions.h>
#import <XCTestPrivate/DTXProxyChannel-XCTestAdditions.h>

#import <objc/runtime.h>

#import <FBControlCore/FBCrashLogCommands.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestConfiguration.h"

static const NSInteger FBProtocolVersion = 36;
static const NSInteger FBProtocolMinimumVersion = 0x8;

static NSTimeInterval BundleReadyTimeout = 60; // Time for `_XCT_testBundleReadyWithProtocolVersion` to be called after the 'connect'.
static NSTimeInterval IDEInterfaceReadyTimeout = 60; // Time for `XCTestManager_IDEInterface` to be returned.
static NSTimeInterval DaemonSessionReadyTimeout = 60; // Time for `_IDE_initiateSessionWithIdentifier` to be returned.
static NSTimeInterval CrashCheckWaitLimit = 120;  // Time to wait for crash report to be generated.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestBundleConnection () <XCTestManager_IDEInterface, XCTMessagingChannel_DaemonToIDE, XCTMessagingChannel_RunnerToIDE>

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget, FBXCTestExtendedCommands> target;
@property (nonatomic, strong, readonly) id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject> interface;
@property (nonatomic, strong, readonly) id<FBLaunchedApplication> testHostApplication;
@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *bundleDisconnected;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *bundleReadyFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *testPlanFuture;

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

- (instancetype)initWithWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget, FBXCTestExtendedCommands>)target interface:(id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject>)interface testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _interface = interface;
  _testHostApplication = testHostApplication;
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

#pragma mark Public

+ (FBFuture<NSNull *> *)connectAndRunBundleToCompletionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget, FBXCTestExtendedCommands>)target interface:(id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject>)interface testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  FBTestBundleConnection *connection = [[self alloc] initWithWithContext:context target:target interface:interface testHostApplication:testHostApplication requestQueue:requestQueue logger:logger];
  return [connection connectAndRunToCompletion];
}

#pragma mark Private
/*
 * Checks if:
 *  - there is a process for the test host application
 *  - the pid of existing process is the same pid we prepared to execute the tests
 * The returned FBFuture will always fail, either with the original error or an error
 * indicating which of the checks above failed.
 */
- (FBFuture<NSNull *> *)performDiagnosisOnBundleConnectionError:(NSError *)error {
  return [[[self.target
             processIDWithBundleID:self.context.testHostLaunchConfiguration.bundleID]
            onQueue:self.requestQueue handleError:^FBFuture *(NSError *pidLookupError) {
    NSString *msg = @"Error while establishing connection to test bundle: "
                    @"The host application is likely to have crashed during startup, "
                    @"but could not find a crash log.";
    // In this case the application lived long enough to avoid a relaunch (see bellow), but crashed before idb could connect to it.
    return [self failedFutureWithCrashLogOrNotFoundErrorDescription:msg];
  }]
  onQueue:self.requestQueue fmap:^FBFuture *(NSNumber *runningPid) {
    if (self.testHostApplication.processIdentifier != runningPid.intValue) {
      NSString *msg = @"Error while establishing connection to test bundle: "
                      @"Running test host application pid is different from the pid launched and set up to execute the tests. "
                      @"The host application is likely to have crashed during startup and been relaunched by iOS.";
      // Sometimes when an application crashes very early (e.g. during dylib loading) iOS retries launching the
      // app with none of the settings idb added in the original launch configuration.
      // idb can't work with this 'vanilla' app process, resulting in errors connecting to the bundle (there won't be a bundle to connect to).
      return [[[FBXCTestError describe:msg] causedBy:error] failFuture];
    }

    // Application process still running.
    // Try to sample process stack.
    return [[[FBProcessFetcher
      performSampleStackshotForProcessIdentifier:self.testHostApplication.processIdentifier
      queue:self.target.workQueue]
    onQueue:self.requestQueue handleError:^FBFuture<NSNull *> *(NSError *_) {
      // Could not sample stack, returning original error
      return [FBFuture futureWithError:error];
    }]
    onQueue:self.requestQueue fmap:^FBFuture<id> *(NSString *stackshot) {
      return [[FBXCTestError
        describeFormat:@"Could not connect to test bundle, but host application process %d is still alive and busy/stalled: %@", self.testHostApplication.processIdentifier, stackshot]
        failFuture];
    }];
  }];
}

- (FBFuture<NSNull *> *)connectAndRunToCompletion
{
  [self.logger log:@"Connecting Test Bundle"];

  __block id<XCTestDriverInterface> testBundleProxy;
  __block DTXConnection *testBundleConnection;

  return [[[[[self
    startTestmanagerdConnection]
    onQueue:self.requestQueue pend:^(DTXConnection *connection) {
      [connection registerDisconnectHandler:^{
        [self.bundleDisconnected resolveWithResult:NSNull.null];
      }];
      testBundleConnection = connection;
      return [FBFuture
        futureWithFutures:@[
          [self setupTestBundleConnectionWithConnection:connection],
          [self sendStartSessionRequestWithConnection:connection],
        ]];
    }]
    onQueue:self.requestQueue pend:^(NSArray<id> *results) {
      [self.logger logFormat:@"Waiting for test bundle to be ready.."];
      testBundleProxy = results[0];
      return [self.bundleReadyFuture timeout:BundleReadyTimeout waitingFor:@"Bundle Ready to be called"];
    }]
    onQueue:self.requestQueue handleError:^(NSError *error) {
      return [self performDiagnosisOnBundleConnectionError:error];
    }]
    onQueue:self.requestQueue pop:^(id result) {
      [self.logger logFormat:@"Starting Execution of the test plan w/ version %ld", FBProtocolVersion];
      [testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
      return self.bundleDisconnectedSuccessfully;
    }];
}

- (FBFutureContext<DTXConnection *> *)startTestmanagerdConnection
{
  id<FBControlCoreLogger> logger = self.logger;
  dispatch_queue_t queue = self.requestQueue;
  [logger log:@"Starting a fresh testmanagerd connection"];
  return [[self.target
    transportForTestManagerService]
    onQueue:queue push:^(NSNumber *socket) {
      return [FBTestBundleConnection connectionWithSocket:socket.intValue queue:queue logger:logger];
    }];
}

+ (FBFutureContext<DTXConnection *> *)connectionWithSocket:(int)socket queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Wrapping testmanagerd socket (%d) in DTXTransport and DTXConnection", socket];
  DTXTransport *transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:socket disconnectAction:^{
    [logger logFormat:@"Notified that daemon socket disconnected"];
  }];
  DTXConnection *connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    [logger logFormat:@"Notified that testmanagerd connection disconnected"];
  }];
  [logger logFormat:@"testmanagerd socket %d wrapped in %@", socket, connection];

  return [[FBFuture
    futureWithResult:connection]
    onQueue:queue contextualTeardown:^(id _, FBFutureState __) {
      [logger logFormat:@"Ending the testmanagerd connection. %@", connection];
      [connection suspend];
      [connection cancel];
      return FBFuture.empty;
    }];
}

- (FBFuture<id<XCTestDriverInterface>> *)setupTestBundleConnectionWithConnection:(DTXConnection *)connection
{
  FBMutableFuture<id<XCTestDriverInterface>> *future = FBMutableFuture.future;
  [self.logger logFormat:@"Listening for proxy connection request from the test bundle (all platforms)"];

  [connection
    xct_handleProxyRequestForInterface:@protocol(XCTMessagingChannel_RunnerToIDE)
    peerInterface:@protocol(XCTMessagingChannel_IDEToRunner)
    handler:^(DTXProxyChannel *channel){
      [self.logger logFormat:@"Got proxy channel request from test bundle"];
      [channel setExportedObject:self queue:self.target.workQueue];
      id<XCTestDriverInterface> interface = channel.remoteObjectProxy;
      [future resolveWithResult:interface];
   }];
  [self.logger logFormat:@"Resuming the test bundle connection."];
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

  [self.logger logFormat:@"Starting test session with ID %@", self.context.sessionIdentifier.UUIDString];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_initiateSessionWithIdentifier:self.context.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:self.class.clientProcessDisplayPath
    protocolVersion:@(FBProtocolVersion)];

  NSString *sessionStartMethod = NSStringFromSelector(@selector(_IDE_initiateSessionWithIdentifier:forClient:atPath:protocolVersion:));

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    [proxyChannel cancel];
    if (error) {
      [self.logger logFormat:@"testmanagerd did %@ failed: %@", sessionStartMethod, error];
      [future resolveWithError:error];
      return;
    }
    [self.logger logFormat:@"testmanagerd handled session request using protocol version requested=%ld received=%ld", FBProtocolVersion, version.longValue];
    [future resolveWithResult:version];
  }];

  return [future timeout:DaemonSessionReadyTimeout waitingFor:@"%@ to be resolved", sessionStartMethod];
}

- (FBFuture<NSNull *> *)bundleDisconnectedSuccessfully
{
  return [[self
    bundleDisconnected]
    onQueue:self.requestQueue fmap:^ FBFuture<NSNull *> * (id _) {
      if (self.testPlanFuture.hasCompleted) {
        [self.logger logFormat:@"Bundle disconnected, with the test plan completed. Bundle exited successfully."];
        return FBFuture.empty;
      }
      [self.logger logFormat:@"Bundle disconnected, but test plan has not completed. This could mean a crash has occured"];
      return [self
               failedFutureWithCrashLogOrNotFoundErrorDescription:@"Lost connection to test process, but could not find a crash log"];
    }];
}

- (FBFuture<NSNull *> *)failedFutureWithCrashLogOrNotFoundErrorDescription:(NSString *)notFoundErrorDescription
{
  return [[[self
    findCrashedProcessLog]
    onQueue:self.target.workQueue chain:^ FBFuture<NSNull *> * (FBFuture<FBCrashLog *> *future) {
      FBCrashLog *crashLog = future.result;
      if (!crashLog) {
        return [[[FBXCTestError
          describe:notFoundErrorDescription]
          code:XCTestBootstrapErrorCodeLostConnection]
          failFuture];
      }
      return [[FBXCTestError
        describeFormat:@"Test Bundle/HostApp Crashed: %@", crashLog]
        failFuture];
    }] mapReplace:NSNull.null];
}

- (FBFuture<FBCrashLog *> *)findCrashedProcessLog
{
  id<FBLaunchedApplication> testHostApplication = self.testHostApplication;
  NSString *testHostBundleID = self.context.testHostLaunchConfiguration.bundleID;
  return [[[self.target
    processIDWithBundleID:self.context.testHostLaunchConfiguration.bundleID]
    onQueue:self.target.workQueue chain:^ FBFuture<FBCrashLogInfo *> * (FBFuture<NSNumber *> *processIdentifierFuture) {
      if (processIdentifierFuture.result) {
        return [[FBControlCoreError
          describeFormat:@"The Process for %@ is not crashed as it is running", processIdentifierFuture.result]
          failFuture];
      }

      id<FBCrashLogCommands> crashLog = (id<FBCrashLogCommands>) self.target;
      if (![crashLog conformsToProtocol:@protocol(FBCrashLogCommands)]) {
        return [[FBControlCoreError
          describeFormat:@"%@ does not conform to %@", self.target, NSStringFromProtocol(@protocol(FBCrashLogCommands))]
          failFuture];
      }

      NSTimeInterval crashWaitTimeout = CrashCheckWaitLimit;
      NSString *crashWaitTimeoutFromEnv = NSProcessInfo.processInfo.environment[@"FBXCTEST_CRASH_WAIT_TIMEOUT"];
      if (crashWaitTimeoutFromEnv) {
        crashWaitTimeout = crashWaitTimeoutFromEnv.floatValue;
      }

      return [[crashLog
        notifyOfCrash:[FBCrashLogInfo predicateForCrashLogsWithProcessID:testHostApplication.processIdentifier]]
        timeout:crashWaitTimeout
        waitingFor:@"Getting crash log for process with pid %d, bunndle ID: %@", testHostApplication.processIdentifier, testHostBundleID];
    }]
    onQueue:self.target.workQueue fmap:^(FBCrashLogInfo *info) {
      NSError *error = nil;
      FBCrashLog *log = [info obtainCrashLogWithError:&error];
      if (!log) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:log];
    }];
}

- (void)concludeWithError:(NSError *)error
{
  [self.logger logFormat:@"Test Completed with error: %@", error];
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

  [self.logger logFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion];
  if (minimumVersionInt > FBProtocolVersion) {
    NSError *error = [[[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]
      code:XCTestBootstrapErrorCodeStartupFailure]
      build];
    [self concludeWithError:error];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    NSError *error = [[[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt]
      code:XCTestBootstrapErrorCodeStartupFailure]
      build];
    [self concludeWithError:error];
    return nil;
  }
  [self.logger logFormat:@"Test Bundle is Ready"];
  [self.bundleReadyFuture resolveWithResult:NSNull.null];
  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

- (id)_XCT_initializationForUITestingDidFailWithError:(NSError *)error
{
  NSError *innerError = [[[[XCTestBootstrapError
    describe:@"Failed to initilize for UI testing"]
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
  [self.logger logFormat:@"Test Bundle is Ready"];

  DTXRemoteInvocationReceipt *receipt = [[objc_lookUpClass("DTXRemoteInvocationReceipt") alloc] init];
  [receipt invokeCompletionWithReturnValue:self.context.testConfiguration.xcTestConfiguration error:nil];

  [self.bundleReadyFuture resolveWithResult:NSNull.null];
  return receipt;
}

@end

#pragma clang diagnostic pop
