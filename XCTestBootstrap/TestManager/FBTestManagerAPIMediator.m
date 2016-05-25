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

#import <FBControlCore/FBControlCore.h>

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestManagerLoggingForwarder.h"
#import "FBTestReporterForwarder.h"
#import "FBTestManagerTestReporter.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestManagerProcessInteractionDelegate.h"

#import "FBTestBundleConnection.h"
#import "FBTestDaemonConnection.h"

const NSInteger FBProtocolVersion = 0x10;
const NSInteger FBProtocolMinimumVersion = 0x8;

@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface>

@property (nonatomic, strong, readonly) DVTDevice *targetDevice;
@property (nonatomic, assign, readonly) BOOL targetIsiOSSimulator;
@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, readonly) FBTestReporterForwarder *reporterForwarder;
@property (nonatomic, strong, readonly) FBXCTestManagerLoggingForwarder *loggingForwarder;

@property (nonatomic, strong, readonly) NSMutableDictionary *tokenToBundleIDMap;

@property (nonatomic, assign, readwrite) BOOL finished;
@property (nonatomic, assign, readwrite) BOOL hasFailed;
@property (nonatomic, assign, readwrite) BOOL testingIsFinished;

@property (nonatomic, strong, readwrite) FBTestBundleConnection *bundleConnection;
@property (nonatomic, strong, readwrite) FBTestDaemonConnection *daemonConnection;

@end

@implementation FBTestManagerAPIMediator

#pragma mark - Initializers

+ (instancetype)mediatorWithDevice:(DVTAbstractiOSDevice *)device processDelegate:(id<FBTestManagerProcessInteractionDelegate>)processDelegate reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier;
{
  return  [[self alloc] initWithDevice:device processDelegate:processDelegate reporter:reporter logger:logger testRunnerPID:testRunnerPID sessionIdentifier:sessionIdentifier];
}

- (instancetype)initWithDevice:(DVTAbstractiOSDevice *)device processDelegate:(id<FBTestManagerProcessInteractionDelegate>)processDelegate reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _targetDevice = device;
  _processDelegate = processDelegate;
  _logger = logger;
  _testRunnerPID = testRunnerPID;
  _sessionIdentifier = sessionIdentifier;

  _targetIsiOSSimulator = [device.class isKindOfClass:NSClassFromString(@"DVTiPhoneSimulator")];
  _tokenToBundleIDMap = [NSMutableDictionary new];
  _requestQueue = dispatch_queue_create("com.facebook.xctestboostrap.mediator", DISPATCH_QUEUE_PRIORITY_DEFAULT);

  _reporterForwarder = [FBTestReporterForwarder withAPIMediator:self reporter:reporter];
  _loggingForwarder = [FBXCTestManagerLoggingForwarder withIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)_reporterForwarder logger:logger];

  _bundleConnection = [FBTestBundleConnection withDevice:device interface:(id)_loggingForwarder sessionIdentifier:sessionIdentifier queue:_requestQueue logger:logger];
  _daemonConnection = [FBTestDaemonConnection withDevice:device interface:(id)_loggingForwarder testRunnerPID:testRunnerPID queue:_requestQueue logger:logger];

  return self;
}

#pragma mark - Public

- (BOOL)connectTestRunnerWithTestManagerDaemonWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (self.finished) {
    return [[XCTestBootstrapError
      describe:@"FBTestManager does not support reconnecting to testmanagerd. You should create new FBTestManager to establish new connection"]
      failBool:error];
  }
  NSError *innerError = nil;
  if (![self.bundleConnection connectWithTimeout:timeout error:&innerError]) {
    return [[[XCTestBootstrapError
      describe:@"Failed to connect to the bundle"]
      causedBy:innerError]
      failBool:error];
  }
  if (![self.daemonConnection connectWithTimeout:timeout error:&innerError]) {
    return [[[XCTestBootstrapError
      describe:@"Failed to connect to the daemon"]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

- (BOOL)executeTestPlanWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.bundleConnection startTestPlanWithError:error] && [self.daemonConnection notifyTestPlanStartedWithError:error];
}

- (void)disconnectTestRunnerAndTestManagerDaemon
{
  self.finished = YES;
  self.testingIsFinished = YES;

  [self.bundleConnection disconnect];
  self.bundleConnection = nil;

  [self.daemonConnection disconnect];
  self.daemonConnection = nil;
}

#pragma mark Reporting

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
    if (error.code != XCTestBootstrapErrorCodeLostConnection) {
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
  if (tests.length == 0) {
    [self.logger logFormat:@"Failing for nil suite identifier."];
    NSError *error = [NSError errorWithDomain:@"IDETestOperationsObserverErrorDomain" code:0x9 userInfo:@{NSLocalizedDescriptionKey : @"Test reported a suite with nil or empty identifier. This is unsupported."}];
    [self finishWithError:error didCancel:NO];
  }

  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.daemonConnection notifyTestPlanEndedWithError:nil];
  return nil;
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  return nil;
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
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
  return nil;
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  return nil;
}

- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 withFailures:(NSNumber *)arg4 unexpected:(NSNumber *)arg5 testDuration:(NSNumber *)arg6 totalDuration:(NSNumber *)arg7
{
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

#pragma mark - Unsupported partly disassembled

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
