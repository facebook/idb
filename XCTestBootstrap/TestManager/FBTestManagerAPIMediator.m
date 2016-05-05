/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerAPIMediator.h"

#import <XCTest/XCTestDriverInterface-Protocol.h>
#import <XCTest/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <DTXConnectionServices/DTXConnection.h>
#import <DTXConnectionServices/DTXProxyChannel.h>
#import <DTXConnectionServices/DTXRemoteInvocationReceipt.h>
#import <DTXConnectionServices/DTXTransport.h>

#import <FBControlCore/FBControlCoreLogger.h>

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#import "XCTestBootstrapError.h"
#import "FBTestManagerTestReporter.h"
#import "FBTestManagerProcessInteractionDelegate.h"

#define weakify(target) __weak __typeof__(target) weak_##target = target
#define strongify(target) \
          _Pragma("clang diagnostic push") \
          _Pragma("clang diagnostic ignored \"-Wshadow\"") \
          __strong __typeof__(weak_##target) self = weak_##target; \
          _Pragma("clang diagnostic pop")


static const NSInteger FBProtocolVersion = 0x10;
static const NSInteger FBProtocolMinimumVersion = 0x8;

static const NSInteger FBErrorCodeStartupFailure = 0x3;
static const NSInteger FBErrorCodeLostConnection = 0x4;


@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface>
@property (nonatomic, strong) DVTDevice *targetDevice;
@property (nonatomic, assign) BOOL targetIsiOSSimulator;

@property (nonatomic, assign) pid_t testRunnerPID;
@property (nonatomic, copy) NSUUID *sessionIdentifier;
@property (nonatomic, strong) NSMutableDictionary *tokenToBundleIDMap;

@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL hasFailed;
@property (nonatomic, assign) BOOL testingIsFinished;
@property (nonatomic, assign) BOOL testPlanDidStartExecuting;

@property (nonatomic, assign) long long testBundleProtocolVersion;
@property (nonatomic, strong) id<XCTestDriverInterface> testBundleProxy;
@property (nonatomic, strong) DTXConnection *testBundleConnection;

@property (nonatomic, assign) long long daemonProtocolVersion;
@property (nonatomic, strong) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (nonatomic, strong) DTXConnection *daemonConnection;

@property (nonatomic, assign) NSTimeInterval defaultTimeout;
@property (nonatomic, strong) NSTimer *startupTimeoutTimer;
@end

@implementation FBTestManagerAPIMediator

+ (NSString *)clientProcessUniqueIdentifier
{
  static dispatch_once_t onceToken;
  static NSString *_clientProcessUniqueIdentifier;
  dispatch_once(&onceToken, ^{
    _clientProcessUniqueIdentifier = [NSProcessInfo processInfo].globallyUniqueString;
  });
  return _clientProcessUniqueIdentifier;
}


#pragma mark - Public

+ (instancetype)mediatorWithDevice:(DVTAbstractiOSDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  FBTestManagerAPIMediator *mediator = [self.class new];
  mediator.defaultTimeout = 120;
  mediator.targetDevice = device;
  mediator.targetIsiOSSimulator = [self isKindOfClass:NSClassFromString(@"DVTiPhoneSimulator")];
  mediator.sessionIdentifier = sessionIdentifier;
  mediator.testRunnerPID = testRunnerPID;
  mediator.tokenToBundleIDMap = [NSMutableDictionary new];
  return mediator;
}

- (BOOL)connectTestRunnerWithTestManagerDaemonWithError:(NSError **)error
{
  if (self.finished) {
    return [[XCTestBootstrapError
      describe:@"FBTestManager does not support reconnecting to testmanagerd. You should create new FBTestManager to establish new connection"]
      failBool:error];
  }
  [self makeTransportWithSuccessBlock:^(DTXTransport *transport) {
    [self setupTestBundleConnectionWithTransport:transport];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self sendStartSessionRequestToTestManager];
    });
  }];
  return YES;
}

- (void)disconnectTestRunnerAndTestManagerDaemon
{
  self.finished = YES;
  self.testingIsFinished = YES;
  self.testRunnerPID = 0;
  self.sessionIdentifier = nil;

  [self.daemonConnection suspend];
  [self.daemonConnection cancel];
  self.daemonConnection = nil;
  self.daemonProxy = nil;
  self.daemonProtocolVersion = 0;

  [self.testBundleConnection suspend];
  [self.testBundleConnection cancel];
  self.testBundleConnection = nil;
  self.testBundleProxy = nil;
  self.testBundleProtocolVersion = 0;

  self.targetDevice = nil;
}

#pragma mark - Private

- (void)setupTestBundleConnectionWithTransport:(DTXTransport *)transport
{
  [self.logger logFormat:@"Creating the connection."];
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];

  weakify(self);
  [connection registerDisconnectHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      strongify(self);
      if (self.testPlanDidStartExecuting) {
        [self reportStartupFailure:@"Lost connection to test process" errorCode:FBErrorCodeLostConnection];
      }
    });
  }];
  [self.logger logFormat:@"Listening for proxy connection request from the test bundle (all platforms)"];
  [connection handleProxyRequestForInterface:@protocol(XCTestManager_IDEInterface)
                               peerInterface:@protocol(XCTestDriverInterface)
                                     handler:^(DTXProxyChannel *channel){
    strongify(self);
    [self.logger logFormat:@"Got proxy channel request from test bundle"];
    [channel setExportedObject:self queue:dispatch_get_main_queue()];
    self.testBundleProxy = channel.remoteObjectProxy;
  }];
  self.testBundleConnection = connection;
  [self.logger logFormat:@"Resuming the connection."];
  [self.testBundleConnection resume];
}

- (void)sendStartSessionRequestToTestManager
{
  if (self.hasFailed) {
    [self.logger logFormat:@"Mediator has already failed skipping."];
    return;
  }

  [self reportStartupProgress:@"Checking test manager availability..." withTimeoutInterval:self.defaultTimeout];
  DTXProxyChannel *proxyChannel =
  [self.testBundleConnection makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
                                               exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [proxyChannel setExportedObject:self queue:dispatch_get_main_queue()];
  id<XCTestManager_DaemonConnectionInterface> remoteProxy = (id<XCTestManager_DaemonConnectionInterface>)[proxyChannel remoteObjectProxy];

  NSString *bundlePath = [NSBundle mainBundle].bundlePath;
  if (![[NSBundle mainBundle].bundlePath.pathExtension isEqualToString:@"app"]) {
    bundlePath = [NSBundle mainBundle].executablePath;
  }

  [self.logger logFormat:@"Starting test session with ID %@", self.sessionIdentifier];

  DTXRemoteInvocationReceipt *receipt =
  [remoteProxy _IDE_initiateSessionWithIdentifier:self.sessionIdentifier
                                        forClient:self.class.clientProcessUniqueIdentifier
                                           atPath:bundlePath
                                  protocolVersion:@(FBProtocolVersion)];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error){
    strongify(self);
    if (!self) {
      [self.logger logFormat:@"Strong self should not be nil"];
      return;
    }
    if (!self) { // Possibly '!error'
      // First if in __54-[_IDETestManagerAPIMediator _handleDaemonConnection:]_block_invoke_2
      [self __beginSessionWithBundlePath:bundlePath remoteProxy:remoteProxy proxyChannel:proxyChannel];
      return;
    }
    [self finilzeConnectionWithProxyChannel:proxyChannel error:error];
  }];
}

- (void)finilzeConnectionWithProxyChannel:(DTXProxyChannel *)proxyChannel error:(NSError *)error
{
  [proxyChannel cancel];
  if (error) {
    [self.logger logFormat:@"Error from testmanagerd: %@ (%@)", error.localizedDescription, error.localizedRecoverySuggestion];
    [self reportStartupFailure:error.localizedDescription errorCode:FBErrorCodeStartupFailure];
    return;
  }
  [self.logger logFormat:@"Testmanagerd handled session request."];
  [self.startupTimeoutTimer invalidate];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.hasFailed) {
      [self.logger logFormat:@"Mediator has already failed skipping."];
      return;
    }
    [self.logger logFormat:@"Waiting for test process to launch."];
  });
}

- (void)whitelistTestProcessIDForUITesting
{
  [self.logger logFormat:@"Creating secondary transport and connection for whitelisting test process PID."];
  [self makeTransportWithSuccessBlock:^(DTXTransport *transport) {
    [self setupDaemonConnectionWithTransport:transport];
  }];
}

- (void)setupDaemonConnectionWithTransport:(DTXTransport *)transport
{
  DTXConnection *connection = [[NSClassFromString(@"DTXConnection") alloc] initWithTransport:transport];
  weakify(self);
  [connection registerDisconnectHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      strongify(self);
      [self reportStartupFailure:@"Lost connection to test manager service." errorCode:FBErrorCodeLostConnection];
    });
  }];
  [self.logger logFormat:@"Resuming the secondary connection."];
  self.daemonConnection = connection;
  [connection resume];
  DTXProxyChannel *channel =
  [connection makeProxyChannelWithRemoteInterface:@protocol(XCTestManager_DaemonConnectionInterface)
                                exportedInterface:@protocol(XCTestManager_IDEInterface)];
  [channel setExportedObject:self queue:dispatch_get_main_queue()];
  self.daemonProxy = (id<XCTestManager_DaemonConnectionInterface>)channel.remoteObjectProxy;

  [self.logger logFormat:@"Whitelisting test process ID %d", self.testRunnerPID];
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID) protocolVersion:@(FBProtocolVersion)];
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (error) {
      [self setupDaemonConnectionViaLegacyProtocol];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self.logger logFormat:@"Got whitelisting response and daemon protocol version %lld", self.daemonProtocolVersion];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:version];
  }];
}

- (void)setupDaemonConnectionViaLegacyProtocol
{
  DTXRemoteInvocationReceipt *receipt = [self.daemonProxy _IDE_initiateControlSessionForTestProcessID:@(self.testRunnerPID)];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (error) {
      [self.logger logFormat:@"Error in whitelisting response from testmanagerd: %@ (%@), ignoring for now.", error.localizedDescription, error.localizedRecoverySuggestion];
      return;
    }
    self.daemonProtocolVersion = version.integerValue;
    [self.logger logFormat:@"Got legacy whitelisting response, daemon protocol version is 14"];
    [self.testBundleProxy _IDE_startExecutingTestPlanWithProtocolVersion:@(FBProtocolVersion)];
  }];
}

- (void)makeTransportWithSuccessBlock:(void(^)(DTXTransport *))successBlock
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error;
    DTXTransport *transport = [self.targetDevice makeTransportForTestManagerService:&error];
    if (error) {
      [self.logger logFormat:@"Failure to create transport for test daemon:\n%@", error.userInfo[@"DetailedDescriptionKey"] ?: @""];
    }
    if (!transport) {
      [self reportStartupFailure:error.localizedFailureReason errorCode:FBErrorCodeStartupFailure];
      return;
    }
    if (successBlock) {
      successBlock(transport);
    }
  });
}

#pragma mark Raporting

- (void)reportStartupProgress:(NSString *)progress withTimeoutInterval:(NSTimeInterval)interval
{
  NSAssert([NSThread isMainThread], @"code should be running on main thread");
  if (!self.testPlanDidStartExecuting) {
    [self.logger logFormat:@"%@, will wait up to %gs", progress, interval];
    [self.startupTimeoutTimer invalidate];
    self.startupTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(startupTimedOut:) userInfo:@{@"description" : progress} repeats:NO];
  }
}

- (void)startupTimedOut:(NSTimer *)timer
{
  [self reportStartupFailure:[NSString stringWithFormat:@"Canceling tests due to timeout in %@", timer.userInfo[@"description"]] errorCode:FBErrorCodeStartupFailure];
}

- (void)reportStartupFailure:(NSString *)failure errorCode:(NSInteger)errorCode
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.finished && !self.hasFailed) {
      self.hasFailed = YES;
      self.finished = YES;
      [self.logger logFormat:@"Test operation failure: %@", failure];
      [self.startupTimeoutTimer invalidate];
      [self finishWithError:[NSError errorWithDomain:@"IDETestOperationsObserverErrorDomain" code:errorCode userInfo:@{NSLocalizedDescriptionKey : failure ?: @"Mystery"}] didCancel:YES];
    }
  });
}


- (void)finishWithError:(NSError *)error didCancel:(BOOL)didCancel
{
  [self.logger logFormat:@"_finishWithError:%@ didCancel: %d", error, didCancel];
  if (self.testingIsFinished) {
    [self.logger logFormat:@"Testing has already finished, ignoring this report."];
    return;
  }
  self.finished = YES;
  self.testingIsFinished = YES;

  if (getenv("XCS")) {
    [self __finishXCS];
    return;
  }

  [self detect_r17733855_fromError:error];
  if (error) {
    NSString *message = @"";
    NSMutableDictionary *userInfo = error.userInfo.mutableCopy;
    if(error.localizedRecoverySuggestion){
      message = error.localizedRecoverySuggestion;
      userInfo[NSLocalizedRecoverySuggestionErrorKey] = message;
    } else if (error.localizedDescription) {
      message = error.localizedDescription;
      userInfo[NSLocalizedDescriptionKey] = message;
    } else if (error.localizedFailureReason) {
      message = error.localizedFailureReason;
      userInfo[NSLocalizedFailureReasonErrorKey] = message;
    }
    error = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
    if (error.code != FBErrorCodeLostConnection) {
      [self.logger logFormat:@"\n\n*** %@\n\n", message];
    }
  }
}


#pragma mark Others

- (void)detect_r17733855_fromError:(NSError *)error
{
  if (!self.targetIsiOSSimulator) {
    return;
  }
  if (!error) {
    return;
  }
  NSString *message = error.localizedDescription;
  if ([message rangeOfString:@"Unable to run app in Simulator"].location != NSNotFound || [message rangeOfString:@"Test session exited(-1) without checking in"].location != NSNotFound ) {
    [self.logger logFormat:@"Detected radar issue r17733855"];
  }
}


#pragma mark - XCTestManager_IDEInterface protocol

#pragma mark Process Launch Delegation

- (id)_XCT_launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment
{
  [self.logger logFormat:@"Test process requested process launch with bundleID %@", bundleID];
  NSError *error;
  DTXRemoteInvocationReceipt *recepit = [NSClassFromString(@"DTXRemoteInvocationReceipt") new];
  if(![self.processDelegate testManagerMediator:self launchProcessWithPath:path bundleID:bundleID arguments:arguments environmentVariables:environment error:&error]) {
    [recepit invokeCompletionWithReturnValue:nil error:error];
  }
  else {
    id token = @(recepit.hash);
    self.tokenToBundleIDMap[token] = bundleID;
    [recepit invokeCompletionWithReturnValue:token error:nil];
  }
  return recepit;
}

- (id)_XCT_getProgressForLaunch:(id)token
{
  [self.logger logFormat:@"Test process requested launch process status with token %@", token];
  DTXRemoteInvocationReceipt *recepit = [NSClassFromString(@"DTXRemoteInvocationReceipt") new];
  [recepit invokeCompletionWithReturnValue:@1 error:nil];
  return recepit;
}

- (id)_XCT_terminateProcess:(id)token
{
  [self.logger logFormat:@"Test process requested process termination with token %@", token];
  NSError *error;
  DTXRemoteInvocationReceipt *recepit = [NSClassFromString(@"DTXRemoteInvocationReceipt") new];
  if (!token) {
    error = [NSError errorWithDomain:@"XCTestIDEInterfaceErrorDomain"
                                code:0x1
                            userInfo:@{NSLocalizedDescriptionKey : @"API violation: token was nil."}];
  }
  else {
    NSString *bundleID = self.tokenToBundleIDMap[token];
    if (!bundleID) {
      error = [NSError errorWithDomain:@"XCTestIDEInterfaceErrorDomain"
                                  code:0x2
                              userInfo:@{NSLocalizedDescriptionKey : @"Invalid or expired token: no matching operation was found."}];
    } else {
      [self.processDelegate testManagerMediator:self killApplicationWithBundleID:bundleID error:&error];
    }
  }
  if (error) {
    [self.logger logFormat:@"Failed to kill process with token %@ dure to %@", token, error];
  }
  [recepit invokeCompletionWithReturnValue:token error:error];
  return recepit;
}

#pragma mark Test Suite Progress

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  [self.logger logFormat:@"_XCT_testSuite:%@ didStartAt:%@", tests, time];
  if (tests.length == 0) {
    [self.logger logFormat:@"Failing for nil suite identifier."];
    NSError *error = [NSError errorWithDomain:@"IDETestOperationsObserverErrorDomain" code:0x9 userInfo:@{NSLocalizedDescriptionKey : @"Test reported a suite with nil or empty identifier. This is unsupported."}];
    [self finishWithError:error didCancel:NO];
  }

  [self.reporter testManagerMediator:self testSuite:tests didStartAt:time];
  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  self.testPlanDidStartExecuting = YES;
  [self.logger logFormat:@"Starting test plan, clearing initialization timeout timer."];
  [self.startupTimeoutTimer invalidate];

  [self.reporter testManagerMediatorDidBeginExecutingTestPlan:self];
  return nil;
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  [self.startupTimeoutTimer invalidate];
  NSInteger protocolVersionInt = protocolVersion.integerValue;
  NSInteger minimumVersionInt = minimumVersion.integerValue;

  self.testBundleProtocolVersion = protocolVersionInt;

  [self.logger logFormat:@"Test bundle is ready, running protocol %ld, requires at least version %ld. IDE is running %ld and requires at least %ld", protocolVersionInt, minimumVersionInt, FBProtocolVersion, FBProtocolMinimumVersion];
  if (minimumVersionInt > FBProtocolVersion) {
    [self reportStartupFailure:[NSString stringWithFormat:@"Protocol mismatch: test process requires at least version %ld, IDE is running version %ld", minimumVersionInt, FBProtocolVersion] errorCode:FBErrorCodeStartupFailure];
    return nil;
  }
  if (protocolVersionInt < FBProtocolMinimumVersion) {
    [self reportStartupFailure:[NSString stringWithFormat:@"Protocol mismatch: IDE requires at least version %ld, test process is running version %ld", FBProtocolMinimumVersion,protocolVersionInt] errorCode:FBErrorCodeStartupFailure];
    return nil;
  }
  if (self.targetDevice.requiresTestDaemonMediationForTestHostConnection) {
    [self whitelistTestProcessIDForUITesting];
    return nil;
  }
  [self _checkUITestingPermissionsForPID:self.testRunnerPID];

  [self.reporter testManagerMediator:self testBundleReadyWithProtocolVersion:protocolVersion minimumVersion:minimumVersion];
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.logger logFormat:@"_XCT_testCaseDidStartForTestClass:%@ method:%@", testClass, method ?: @""];
  [self.reporter testManagerMediator:self testCaseDidStartForTestClass:testClass method:method];
  return nil;
}

// This looks like tested application logs
- (id)_XCT_logDebugMessage:(NSString *)debugMessage
{
  return nil;
}

// ?
- (id)_XCT_logMessage:(NSString *)message
{
  [self.logger logFormat:@"MAGIC_MESSAGE: %@", message];
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.reporter testManagerMediatorDidFinishExecutingTestPlan:self];
  return nil;
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)arg1 method:(NSString *)arg2 withStatus:(NSString *)arg3 duration:(NSNumber *)arg4
{
  [self.reporter testManagerMediator:self testCaseDidFinishForTestClass:arg1 method:arg2 withStatus:arg3 duration:arg4];
  return nil;
}

- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 withFailures:(NSNumber *)arg4 unexpected:(NSNumber *)arg5 testDuration:(NSNumber *)arg6 totalDuration:(NSNumber *)arg7
{
  [self.reporter testManagerMediator:self testSuite:arg1 didFinishAt:arg2 runCount:arg3 withFailures:arg4 unexpected:arg5 testDuration:arg6 totalDuration:arg7];
  return nil;
}

#pragma mark - Unimplemented

- (id)_XCT_nativeFocusItemDidChangeAtTime:(NSNumber *)arg1 parameterSnapshot:(XCElementSnapshot *)arg2 applicationSnapshot:(XCElementSnapshot *)arg3
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedEventNames:(NSArray *)arg1 timestamp:(NSNumber *)arg2 duration:(NSNumber *)arg3 startLocation:(NSDictionary *)arg4 startElementSnapshot:(XCElementSnapshot *)arg5 startApplicationSnapshot:(XCElementSnapshot *)arg6 endLocation:(NSDictionary *)arg7 endElementSnapshot:(XCElementSnapshot *)arg8 endApplicationSnapshot:(XCElementSnapshot *)arg9
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCase:(NSString *)arg1 method:(NSString *)arg2 didFinishActivity:(XCActivityRecord *)arg3
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCase:(NSString *)arg1 method:(NSString *)arg2 willStartActivity:(XCActivityRecord *)arg3
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedOrientationChange:(NSString *)arg1
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedFirstResponderChangedWithApplicationSnapshot:(XCElementSnapshot *)arg1
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_exchangeCurrentProtocolVersion:(NSNumber *)arg1 minimumVersion:(NSNumber *)arg2
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedKeyEventsWithApplicationSnapshot:(XCElementSnapshot *)arg1 characters:(NSString *)arg2 charactersIgnoringModifiers:(NSString *)arg3 modifierFlags:(NSNumber *)arg4
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedEventNames:(NSArray *)arg1 duration:(NSNumber *)arg2 startLocation:(NSDictionary *)arg3 startElementSnapshot:(XCElementSnapshot *)arg4 startApplicationSnapshot:(XCElementSnapshot *)arg5 endLocation:(NSDictionary *)arg6 endElementSnapshot:(XCElementSnapshot *)arg7 endApplicationSnapshot:(XCElementSnapshot *)arg8
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedKeyEventsWithCharacters:(NSString *)arg1 charactersIgnoringModifiers:(NSString *)arg2 modifierFlags:(NSNumber *)arg3
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedEventNames:(NSArray *)arg1 duration:(NSNumber *)arg2 startElement:(XCAccessibilityElement *)arg3 startApplicationSnapshot:(XCElementSnapshot *)arg4 endElement:(XCAccessibilityElement *)arg5 endApplicationSnapshot:(XCElementSnapshot *)arg6
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedEvent:(NSString *)arg1 targetElementID:(NSDictionary *)arg2 applicationSnapshot:(XCElementSnapshot *)arg3
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_recordedEvent:(NSString *)arg1 forElement:(NSString *)arg2
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testMethod:(NSString *)arg1 ofClass:(NSString *)arg2 didMeasureMetric:(NSDictionary *)arg3 file:(NSString *)arg4 line:(NSNumber *)arg5
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCase:(NSString *)arg1 method:(NSString *)arg2 didStallOnMainThreadInFile:(NSString *)arg3 line:(NSNumber *)arg4
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)arg1 method:(NSString *)arg2 withMessage:(NSString *)arg3 file:(NSString *)arg4 line:(NSNumber *)arg5
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testMethod:(NSString *)arg1 ofClass:(NSString *)arg2 didMeasureValues:(NSArray *)arg3 forPerformanceMetricID:(NSString *)arg4 name:(NSString *)arg5 withUnits:(NSString *)arg6 baselineName:(NSString *)arg7 baselineAverage:(NSNumber *)arg8 maxPercentRegression:(NSNumber *)arg9 maxPercentRelativeStandardDeviation:(NSNumber *)arg10 file:(NSString *)arg11 line:(NSNumber *)arg12
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testBundleReady
{
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (NSString *)unknownMessageForSelector:(SEL)aSelector
{
  return [NSString stringWithFormat:@"Received call for unhandled method (%@). Probably you should have a look at _IDETestManagerAPIMediator in IDEFoundation.framework and implement it. Good luck!", NSStringFromSelector(aSelector)];
}

// This will add more logs when unimplemented method from XCTestManager_IDEInterface protocol is called
- (id)handleUnimplementedXCTRequest:(SEL)aSelector
{
  [self.logger log:[self unknownMessageForSelector:aSelector]];
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
  return nil;
}

// This method name reflects method in _IDETestManagerAPIMediator
- (void)_checkUITestingPermissionsForPID:(int)pid
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
}


#pragma mark - Unsupported partly disassembled

- (void)__beginSessionWithBundlePath:(NSString *)bundlePath remoteProxy:(id<XCTestManager_DaemonConnectionInterface>)remoteProxy proxyChannel:(DTXProxyChannel *)proxyChannel
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
  DTXRemoteInvocationReceipt *receipt = [remoteProxy _IDE_beginSessionWithIdentifier:self.sessionIdentifier
                                                                                       forClient:self.class.clientProcessUniqueIdentifier
                                                                                          atPath:bundlePath];
  weakify(self);
  [receipt handleCompletion:^(NSNumber *version, NSError *error) {
    strongify(self);
    if (!self) {
      [self.logger logFormat:@"(strongSelf) should not be nil"];
      return;
    }
    [self finilzeConnectionWithProxyChannel:proxyChannel error:error];
  }];
}

- (void)__finishXCS
{
  NSAssert(nil, [self unknownMessageForSelector:_cmd]);
  [self.targetDevice _syncDeviceCrashLogsDirectoryWithCompletionHandler:^(NSError *crashLogsSyncError){
    dispatch_async(dispatch_get_main_queue(), ^{
      CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
      if (crashLogsSyncError) {
        [self.logger logFormat:@"Error syncing device diagnostic logs after %.1fs: %@", time, crashLogsSyncError];
      }
      else {
        [self.logger logFormat:@"Finished syncing device diagnostic logs after %.1fs.", time];
      }
    });
  }];
}

@end
