/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestBundleConnection.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>
#import <DTXConnectionServices/DTXSocketTransport.h>

#import <objc/runtime.h>

#import <FBControlCore/FBCrashLogCommands.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerAPIMediator.h"

static NSTimeInterval BundleReadyTimeout = 20; // Time for `_XCT_testBundleReadyWithProtocolVersion` to be called after the 'connect'.
static NSTimeInterval IDEInterfaceReadyTimeout = 10; // Time for `XCTestManager_IDEInterface` to be returned.
static NSTimeInterval DaemonSessionReadyTimeout = 10; // Time for `_IDE_initiateSessionWithIdentifier` to be returned.
static NSTimeInterval CrashCheckWaitLimit = 30;  // Time to wait for crash report to be generated.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestBundleConnection () <XCTestManager_IDEInterface>

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) id<FBLaunchedApplication> testHostApplication;
@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *bundleDisconnected;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *bundleReadyFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *testPlanFuture;

@property (atomic, strong, nullable, readwrite) id<XCTestDriverInterface> testBundleProxy;
@property (atomic, strong, nullable, readwrite) DTXConnection *testBundleConnection;
@property (atomic, strong, nullable, readwrite) NSDate *applicationLaunchDate;

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

+ (FBFutureContext<FBTestBundleConnection *> *)bundleConnectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
{
  FBTestBundleConnection *connection = [[self alloc] initWithWithContext:context target:target interface:interface testHostApplication:testHostApplication requestQueue:requestQueue logger:logger];
  return [connection connect];
}

- (instancetype)initWithWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger
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

- (FBFuture<NSNull *> *)runTestPlanUntilCompletion
{
  return [FBFuture
    onQueue:self.requestQueue resolve:^ FBFuture<NSNull *> * {
      id<XCTestDriverInterface> testBundleProxy = self.testBundleProxy;
      if (!testBundleProxy) {
        return [[XCTestBootstrapError
          describeFormat:@"runTestPlanUntilCompletion called before bundle proxy created"]
          failFuture];
      }
      [self.logger logFormat:@"Starting Execution of the test plan w/ version %ld", FBProtocolVersion];
      [testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
      return self.bundleDisconnectedSuccessfully;
    }];
}

#pragma mark Private

- (FBFutureContext<FBTestBundleConnection *> *)connect
{
  [self.logger log:@"Connecting Test Bundle"];

  return [[[[FBTestManagerAPIMediator
    testmanagerdConnectionWithTarget:self.target queue:self.requestQueue logger:self.logger]
    onQueue:self.requestQueue pend:^(DTXConnection *connection) {
      [connection registerDisconnectHandler:^{
        [self.bundleDisconnected resolveWithResult:NSNull.null];
      }];
      self.testBundleConnection = connection;
      return [FBFuture
        futureWithFutures:@[
          [self setupTestBundleConnectionWithConnection:connection],
          [self sendStartSessionRequestWithConnection:connection],
        ]];
    }]
    onQueue:self.requestQueue pend:^(NSArray<id> *results) {
      [self.logger logFormat:@"Waiting for test bundle to be ready.."];
      id<XCTestDriverInterface> testBundleProxy = results[0];
      self.testBundleProxy = testBundleProxy;
      return [[self.bundleReadyFuture
        timeout:BundleReadyTimeout waitingFor:@"Bundle Ready to be called"]
        mapReplace:self];
    }]
    onQueue:self.requestQueue contextualTeardown:^(id _, FBFutureState __) {
      self.testBundleProxy = nil;
      self.testBundleConnection = nil;
      return FBFuture.empty;
    }];
}

- (FBFuture<id<XCTestDriverInterface>> *)setupTestBundleConnectionWithConnection:(DTXConnection *)connection
{
  FBMutableFuture<id<XCTestDriverInterface>> *future = FBMutableFuture.future;
  [self.logger logFormat:@"Listening for proxy connection request from the test bundle (all platforms)"];

  [connection
    handleProxyRequestForInterface:@protocol(XCTestManager_IDEInterface)
    peerInterface:@protocol(XCTestDriverInterface)
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
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [proxyChannel setExportedObject:self queue:self.target.workQueue];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>) proxyChannel.remoteObjectProxy;

  [self.logger logFormat:@"Starting test session with ID %@", self.context.sessionIdentifier.UUIDString];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_initiateSessionWithIdentifier:self.context.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:self.class.clientProcessDisplayPath
    protocolVersion:@(FBProtocolVersion)];

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    if (error || !version) {
      [self.logger logFormat:@"Client Daemon Interface failed, trying legacy format."];
      [future resolveFromFuture:[self setupLegacyProtocolConnectionViaRemoteProxy:remoteProxy proxyChannel:proxyChannel]];
      return;
    }
    [future resolveWithResult:version];
    [self.logger logFormat:@"testmanagerd handled session request using protcol version %ld.", (long)FBProtocolVersion];
    [proxyChannel cancel];
  }];

  return [future timeout:DaemonSessionReadyTimeout waitingFor:@"_IDE_initiateSessionWithIdentifier to be resolved"];
}

- (FBFuture<NSNumber *> *)setupLegacyProtocolConnectionViaRemoteProxy:(id<XCTestManager_DaemonConnectionInterface>)remoteProxy proxyChannel:(DTXProxyChannel *)proxyChannel
{
  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_beginSessionWithIdentifier:self.context.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:self.class.clientProcessDisplayPath];

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      NSError *innerError = [[[XCTestBootstrapError
        describe:@"Client Daemon Interface failed"]
        causedBy:error]
        build];
      [future resolveWithError:innerError];
      return;
    }

    [future resolveWithResult:version];
    [self.logger logFormat:@"testmanagerd handled session request using legacy protocol %@", version];
    [proxyChannel cancel];
  }];

  return future;
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
      return [[self
        findCrashedProcessLog]
        onQueue:self.target.workQueue chain:^ FBFuture<NSNull *> * (FBFuture<FBCrashLog *> *future) {
          FBCrashLog *crashLog = future.result;
          if (!crashLog) {
            return [[[XCTestBootstrapError
              describeFormat:@"Lost connection to test process, but could not find a crash log"]
              code:XCTestBootstrapErrorCodeLostConnection]
              failFuture];
          }
          return [[XCTestBootstrapError
            describeFormat:@"Test Bundle Crashed: %@", crashLog]
            failFuture];
        }];
    }];
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

- (id)_XCT_testRunnerReadyWithCapabilities:(XCTCapabilities *)arg1
{
  [self.logger logFormat:@"Test Bundle is Ready"];
  [self.bundleReadyFuture resolveWithResult:NSNull.null];
  return nil;
}

@end

#pragma clang diagnostic pop
