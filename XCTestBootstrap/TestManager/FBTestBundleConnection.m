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

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"
#import "FBDeviceOperator.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestBundleResult.h"

static NSTimeInterval CrashCheckInterval = 0.5;

/**
 An Enumeration of mutually exclusive states of the connection
 */
typedef NS_ENUM(NSUInteger, FBTestBundleConnectionState) {
  FBTestBundleConnectionStateNotConnected = 0,
  FBTestBundleConnectionStateConnecting = 1,
  FBTestBundleConnectionStateTestBundleReady = 2,
  FBTestBundleConnectionStateAwaitingStartOfTestPlan = 3,
  FBTestBundleConnectionStateRunningTestPlan = 4,
  FBTestBundleConnectionStateEndedTestPlan = 5,
  FBTestBundleConnectionStateResultAvailable = 6,
};

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestBundleConnection () <XCTestManager_IDEInterface>

@property (atomic, assign, readwrite) FBTestBundleConnectionState state;
@property (atomic, strong, readwrite) FBTestBundleResult *result;

@property (atomic, assign, readwrite) long long testBundleProtocolVersion;
@property (atomic, nullable, strong, readwrite) id<XCTestDriverInterface> testBundleProxy;
@property (atomic, nullable, strong, readwrite) DTXConnection *testBundleConnection;
@property (atomic, nullable, strong, readwrite) NSDate *lastCrashCheckDate;

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

  _state = FBTestBundleConnectionStateNotConnected;
  _lastCrashCheckDate = NSDate.distantPast;

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

- (nullable FBTestBundleResult *)connectWithTimeout:(NSTimeInterval)timeout
{
  NSAssert(NSThread.isMainThread, @"-[%@ %@] should be called from the main thread", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  if (self.state != FBTestBundleConnectionStateNotConnected) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Cannot connect, state must be %@ but is %@", [FBTestBundleConnection stateStringForState:FBTestBundleConnectionStateNotConnected], [FBTestBundleConnection stateStringForState:self.state]];
    return [self concludeWithResult:[FBTestBundleResult failedInError:error]];
  }

  [self connect];
  BOOL waitSuccess = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.state != FBTestBundleConnectionStateConnecting;
  }];

  if (!waitSuccess) {
    XCTestBootstrapError *error = [XCTestBootstrapError describe:@"Timeout establishing connection"];
    return [self concludeWithResult:[FBTestBundleResult failedInError:error]];
  }
  if (self.state == FBTestBundleConnectionStateResultAvailable) {
    return self.result;
  }
  return nil;
}

- (nullable FBTestBundleResult *)startTestPlan
{
  if (self.state != FBTestBundleConnectionStateTestBundleReady) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"State should be '%@' got '%@", [FBTestBundleConnection stateStringForState:FBTestBundleConnectionStateTestBundleReady], [FBTestBundleConnection stateStringForState:self.state]];
    return [self concludeWithResult:[FBTestBundleResult failedInError:error]];
  }

  [self.logger log:@"Bundle Connection scheduling start of Test Plan"];
  self.state = FBTestBundleConnectionStateAwaitingStartOfTestPlan;
  dispatch_async(self.queue, ^{
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
  });
  return nil;
}

- (nullable FBTestBundleResult *)checkForResult
{
  if (self.result) {
    return self.result;
  }
  if (self.shouldCheckForCrashedProcess) {
    return [self checkForCrashedProcess];
  }
  return nil;
}

- (FBTestBundleResult *)disconnect
{
  [self.logger logFormat:@"Disconnecting Test Bundle in state '%@'", [FBTestBundleConnection stateStringForState:self.state]];

  FBTestBundleResult *result = nil;
  if (self.state == FBTestBundleConnectionStateEndedTestPlan) {
    result = [self concludeWithResult:FBTestBundleResult.success];
  } else {
    result = [self concludeWithResult:FBTestBundleResult.clientRequestedDisconnect];
  }
  [self.testBundleConnection suspend];
  [self.testBundleConnection cancel];
  self.testBundleConnection = nil;
  self.testBundleProxy = nil;
  self.testBundleProtocolVersion = 0;

  return result;
}

#pragma mark Private

- (void)connect
{
  self.state = FBTestBundleConnectionStateConnecting;
  [self.logger log:@"Connecting Test Bundle"];
  dispatch_async(self.queue, ^{
    NSError *error;
    DTXTransport *transport = [self.deviceOperator makeTransportForTestManagerServiceWithLogger:self.logger error:&error];
    if (error || !transport) {
      XCTestBootstrapError *realError = [[XCTestBootstrapError
        describe:@"Failed to create transport"]
        causedBy:error];
      [self concludeWithResult:[FBTestBundleResult failedInError:realError]];
      return;
    }
    DTXConnection *connection = [self setupTestBundleConnectionWithTransport:transport];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self sendStartSessionRequestWithConnection:connection];
    });
  });
}

- (DTXConnection *)setupTestBundleConnectionWithTransport:(DTXTransport *)transport
{
  [self.logger logFormat:@"Creating the test bundle connection."];
  DTXConnection *connection = [[objc_lookUpClass("DTXConnection") alloc] initWithTransport:transport];
  [connection registerDisconnectHandler:^{
    [self bundleDisconnectedWithState:self.state];
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

- (void)sendStartSessionRequestWithConnection:(DTXConnection *)connection
{
  [self.logger log:@"Checking test manager availability..."];
  DTXProxyChannel *proxyChannel = [self.testBundleConnection
    makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
    exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [proxyChannel setExportedObject:self queue:dispatch_get_main_queue()];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>) proxyChannel.remoteObjectProxy;

  [self.logger logFormat:@"Starting test session with ID %@", self.context.sessionIdentifier.UUIDString];

  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_initiateSessionWithIdentifier:self.context.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:self.class.clientProcessDisplayPath
    protocolVersion:@(FBProtocolVersion)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    if (error || !version) {
      [self.logger logFormat:@"Client Daemon Interface failed, trying legacy format."];
      [self setupLegacyProtocolConnectionViaRemoteProxy:remoteProxy proxyChannel:proxyChannel];
      return;
    }

    [self.logger logFormat:@"testmanagerd handled session request using protcol version %ld.", (long)FBProtocolVersion];
    [proxyChannel cancel];
  }];
}

- (DTXRemoteInvocationReceipt *)setupLegacyProtocolConnectionViaRemoteProxy:(id<XCTestManager_DaemonConnectionInterface>)remoteProxy proxyChannel:(DTXProxyChannel *)proxyChannel
{
  DTXRemoteInvocationReceipt *receipt = [remoteProxy
    _IDE_beginSessionWithIdentifier:self.context.sessionIdentifier
    forClient:self.class.clientProcessUniqueIdentifier
    atPath:self.class.clientProcessDisplayPath];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    if (error) {
      [self concludeWithResult:[FBTestBundleResult failedInError:[[XCTestBootstrapError describe:@"Client Daemon Interface failed"] causedBy:error]]];
      return;
    }

    [self.logger logFormat:@"testmanagerd handled session request using legacy protocol."];
    [proxyChannel cancel];
  }];
  return receipt;
}

- (void)bundleDisconnectedWithState:(FBTestBundleConnectionState)state
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.logger logFormat:@"Bundle Connection Disconnected in state '%@'", [FBTestBundleConnection stateStringForState:state]];

    if (self.result) {
      return;
    }
    if (self.state == FBTestBundleConnectionStateEndedTestPlan) {
      [self concludeWithResult:FBTestBundleResult.success];
      return;
    }

    if ([self checkForCrashedProcess]) {
      return;
    }
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describeFormat:@"Lost connection to test process with state '%@'", [FBTestBundleConnection stateStringForState:state]]
      code:XCTestBootstrapErrorCodeLostConnection];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
  });
}

- (BOOL)shouldCheckForCrashedProcess
{
  if (!FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return NO;
  }

  return [NSDate.date isGreaterThanOrEqualTo:[self.lastCrashCheckDate dateByAddingTimeInterval:CrashCheckInterval]];
}

- (nullable FBTestBundleResult *)checkForCrashedProcess
{
  // Set the Crash Date Check.
  self.lastCrashCheckDate = NSDate.date;

  NSError *innerError;
  pid_t pid = [self.deviceOperator processIDWithBundleID:self.context.testRunnerBundleID error:&innerError];
  if (pid >= 1) {
    return nil;
  }
  // It make some time for the diagnostic to appear.
  FBDiagnostic *diagnostic = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^ FBDiagnostic * {
    return [self.deviceOperator attemptToFindCrashLogForProcess:self.context.testRunnerPID bundleID:self.context.testRunnerBundleID];
  }];
  if (!diagnostic.hasLogContent) {
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describe:@"Test Process likely crashed but a crash log could not be obtained"]
      code:XCTestBootstrapErrorCodeLostConnection];
    return [self concludeWithResult:[FBTestBundleResult failedInError:error]];
  }
  FBTestBundleResult *result = [FBTestBundleResult bundleCrashedDuringTestRun:diagnostic];
  return [self concludeWithResult:result];
}

- (FBTestBundleResult *)concludeWithResult:(FBTestBundleResult *)result
{
  [self.logger logFormat:@"Test Completed with Result: %@", result];
  self.result = result;
  self.state = FBTestBundleConnectionStateResultAvailable;
  return result;
}

#pragma mark XCTestDriverInterface

- (id)_XCT_didBeginExecutingTestPlan
{
  if (self.state != FBTestBundleConnectionStateAwaitingStartOfTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Test Plan Started, but state is %@", [FBTestBundleConnection stateStringForState:self.state]];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
    return nil;
  }
  [self.logger logFormat:@"Test Plan Started"];
  self.state = FBTestBundleConnectionStateRunningTestPlan;
  return [self.interface _XCT_didBeginExecutingTestPlan];
}

- (id)_XCT_didFinishExecutingTestPlan
{
  if (self.state != FBTestBundleConnectionStateRunningTestPlan) {
    XCTestBootstrapError *error = [XCTestBootstrapError
      describeFormat:@"Test Plan Ended, but state is %@", [FBTestBundleConnection stateStringForState:self.state]];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
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
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion]
      code:XCTestBootstrapErrorCodeStartupFailure];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describeFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt]
      code:XCTestBootstrapErrorCodeStartupFailure];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
    return nil;
  }
  if (!self.deviceOperator.requiresTestDaemonMediationForTestHostConnection) {
    XCTestBootstrapError *error = [[XCTestBootstrapError
      describe:@"Test Bundle Connection cannot handle a Device that doesn't require daemon mediation"]
      code:XCTestBootstrapErrorCodeStartupFailure];
    [self concludeWithResult:[FBTestBundleResult failedInError:error]];
    return nil;
  }

  [self.logger logFormat:@"Test Bundle is Ready"];
  self.state = FBTestBundleConnectionStateTestBundleReady;
  return [self.interface _XCT_testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
}

- (id)_XCT_didBeginInitializingForUITesting
{
  [self.logger log:@"Started initilizing for UI testing."];
  return nil;
}

- (id)_XCT_initializationForUITestingDidFailWithError:(NSError *)error
{
  XCTestBootstrapError *trueError = [[[XCTestBootstrapError
    describe:@"Failed to initilize for UI testing"]
    causedBy:error]
   code:XCTestBootstrapErrorCodeStartupFailure];
  [self concludeWithResult:[FBTestBundleResult failedInError:trueError]];
  return nil;
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
    case FBTestBundleConnectionStateResultAvailable:
      return @"result available";
    default:
      return @"unknown";
  }
}

@end

#pragma clang diagnostic pop
