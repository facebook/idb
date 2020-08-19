/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestManagerLoggingForwarder.h"

#import "FBTestReporterForwarder.h"
#import "FBTestManagerTestReporter.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestBundleConnection.h"
#import "FBTestDaemonConnection.h"
#import "FBTestManagerContext.h"
#import "FBTestBundleResult.h"
#import "FBTestManagerResult.h"
#import "FBTestDaemonResult.h"
#import "FBTestApplicationLaunchStrategy.h"

const NSInteger FBProtocolVersion = 0x16;
const NSInteger FBProtocolMinimumVersion = 0x8;

@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface>

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) id<FBTestManagerTestReporter> reporter;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, nullable, readonly) NSDictionary<NSString *, NSString *> *testedApplicationAdditionalEnvironment;

@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, readonly) FBTestReporterForwarder *reporterForwarder;
@property (nonatomic, strong, readonly) FBXCTestManagerLoggingForwarder *loggingForwarder;
@property (nonatomic, strong, readonly) NSMutableDictionary *tokenToBundleIDMap;

@property (nonatomic, strong, readonly) FBTestBundleConnection *bundleConnection;
@property (nonatomic, strong, readonly) FBTestDaemonConnection *daemonConnection;
@property (nonatomic, strong, nullable, readwrite) FBTestManagerResult *result;

@end

@implementation FBTestManagerAPIMediator

#pragma mark - Initializers

+ (instancetype)mediatorWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  return  [[self alloc] initWithContext:context target:target reporter:reporter logger:logger testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];
}

- (instancetype)initWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _reporter = reporter;
  _logger = logger;
  _testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment;

  _tokenToBundleIDMap = [NSMutableDictionary new];
  _requestQueue = dispatch_queue_create("com.facebook.xctestboostrap.mediator", DISPATCH_QUEUE_PRIORITY_DEFAULT);

  _reporterForwarder = [FBTestReporterForwarder withAPIMediator:self reporter:reporter];
  _loggingForwarder = [FBXCTestManagerLoggingForwarder withIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)_reporterForwarder logger:logger];

  _bundleConnection = [FBTestBundleConnection connectionWithContext:context target:target interface:(id)_loggingForwarder requestQueue:_requestQueue logger:logger];
  _daemonConnection = [FBTestDaemonConnection connectionWithContext:context target:target interface:(id)_loggingForwarder requestQueue:_requestQueue logger:logger];

  return self;
}

#pragma mark - NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"TestManager %@ for (%@)",
    self.result ?: @"Awaiting Result",
    self.context
  ];
}

#pragma mark - Public

- (FBFuture<FBTestManagerResult *> *)connect
{
  if (self.result) {
    [self.logger.error log:@"FBTestManager does not support reconnecting to testmanagerd. You should create new FBTestManager to establish new connection"];
    return [FBFuture futureWithResult:self.result];
  }
  return [self.bundleConnection.connect
    onQueue:self.target.workQueue
    fmap:^(FBTestBundleResult *bundleResult) {
      if (!bundleResult.didEndSuccessfully) {
        return [FBFuture futureWithResult:[FBTestManagerResult bundleConnectionFailed:bundleResult]];
      }
      return [self.daemonConnection.connect
        onQueue:self.target.workQueue map:^(FBTestDaemonResult *daemonResult) {
          if (!daemonResult.didEndSuccessfully) {
            return [FBTestManagerResult daemonConnectionFailed:daemonResult];
          }
          return [FBTestManagerResult success];
        }];
    }];
}

- (FBFuture<FBTestManagerResult *> *)execute
{
  id<FBTestManagerTestReporter> reporter = self.reporter;
  return [[[FBFuture
    futureWithFutures:@[self.bundleConnection.startTestPlan, self.daemonConnection.notifyTestPlanStarted]]
    onQueue:self.target.workQueue fmap:^FBFuture *(FBTestManagerResult *result) {
      return [FBFuture futureWithFutures:@[self.bundleConnection.completeTestRun, self.daemonConnection.completed]];
    }]
    onQueue:self.target.workQueue chain:^ FBFuture <FBTestManagerResult *> * (FBFuture<NSArray<id> *> *future){
      NSError *error = future.error;
      if (error) {
        [reporter testManagerMediator:self testPlanDidFailWithMessage:error.description];
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:FBTestManagerResult.success];
    }];
}

- (FBFuture<FBTestManagerResult *> *)disconnect
{
  return [[FBFuture
    futureWithFutures:@[[self.bundleConnection disconnect], [self.daemonConnection disconnect]]]
    onQueue:self.target.workQueue map:^(id _) {
      if (self.result) {
        return [FBFuture futureWithResult:self.result];
      }
      return [FBFuture futureWithResult:[self concludeWithResult:FBTestManagerResult.clientRequestedDisconnect]];
    }];
}

#pragma mark Reporting

- (FBTestManagerResult *)concludeWithResult:(FBTestManagerResult *)result
{
  if (self.result) {
    return self.result;
  }

  self.result = result;
  return result;
}

#pragma mark - XCTestManager_IDEInterface protocol

#pragma mark Process Launch Delegation

- (id)_XCT_launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment
{
  [self.logger logFormat:@"Test process requested process launch with bundleID %@", bundleID];
  NSMutableDictionary<NSString *, NSString *> *targetEnvironment = @{}.mutableCopy;
  [targetEnvironment addEntriesFromDictionary:self.testedApplicationAdditionalEnvironment];
  [targetEnvironment addEntriesFromDictionary:environment];


  NSError *error = nil;
  FBProcessOutputConfiguration *processOutput = [FBProcessOutputConfiguration
    configurationWithStdOut:[FBLoggingDataConsumer consumerWithLogger:self.logger]
    stdErr:[FBLoggingDataConsumer consumerWithLogger:self.logger]
    error:&error];
  NSAssert(processOutput, @"Could not construct application output configuration %@", error);

  DTXRemoteInvocationReceipt *receipt = [objc_lookUpClass("DTXRemoteInvocationReceipt") new];
  FBApplicationLaunchConfiguration *launch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:bundleID
    bundleName:bundleID
    arguments:arguments
    environment:targetEnvironment
    output:processOutput
    launchMode:FBApplicationLaunchModeFailIfRunning];
  id token = @(receipt.hash);

  [[[FBTestApplicationLaunchStrategy
    strategyWithTarget:self.target]
    launchApplication:launch atPath:path]
    onQueue:self.target.workQueue notifyOfCompletion:^(FBFuture<NSNull *> *future) {
      NSError *innerError = future.error;
      if (innerError) {
        [receipt invokeCompletionWithReturnValue:nil error:innerError];
      } else {
        self.tokenToBundleIDMap[token] = bundleID;
        [receipt invokeCompletionWithReturnValue:token error:nil];
      }
    }];

  return receipt;
}

- (id)_XCT_getProgressForLaunch:(id)token
{
  [self.logger logFormat:@"Test process requested launch process status with token %@", token];
  DTXRemoteInvocationReceipt *receipt = [objc_lookUpClass("DTXRemoteInvocationReceipt") new];
  [receipt invokeCompletionWithReturnValue:@1 error:nil];
  return receipt;
}

- (id)_XCT_terminateProcess:(id)token
{
  [self.logger logFormat:@"Test process requested process termination with token %@", token];
  NSError *error;
  DTXRemoteInvocationReceipt *receipt = [objc_lookUpClass("DTXRemoteInvocationReceipt") new];
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
        [[self.target killApplicationWithBundleID:bundleID]
         onQueue:self.target.workQueue notifyOfCompletion:^(FBFuture<NSNull *> *future) {
            [receipt invokeCompletionWithReturnValue:token error:future.error];
        }];
    }
  }
  if (error) {
    [self.logger logFormat:@"Failed to kill process with token %@ dure to %@", token, error];
  }
  return receipt;
}

#pragma mark iOS 10.x

- (id)_XCT_didBeginInitializingForUITesting
{
  return nil;
}

- (id)_XCT_initializationForUITestingDidFailWithError:(NSError *)error
{
  return nil;
}

- (id)_XCT_handleCrashReportData:(NSData *)arg1 fromFileWithName:(NSString *)arg2
{
  return nil;
}

#pragma mark Test Suite Progress

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  if (tests.length == 0) {
    XCTestBootstrapError *error = [[[XCTestBootstrapError
      describe:@"Test reported a suite with nil or empty identifier. This is unsupported."]
      inDomain:@"IDETestOperationsObserverErrorDomain"]
      code:0x9];
    [self concludeWithResult:[FBTestManagerResult internalError:error]];
  }

  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.daemonConnection notifyTestPlanEnded];
  [self.daemonConnection disconnect];
  [self.bundleConnection disconnect];
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

- (id)_XCT_testCase:(NSString *)arg1 method:(NSString *)arg2 didFinishActivity:(XCActivityRecord *)arg3
{
  return nil;
}

- (id)_XCT_testCase:(NSString *)arg1 method:(NSString *)arg2 willStartActivity:(XCActivityRecord *)arg3
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

- (id)_XCT_testRunnerReadyWithCapabilities:(XCTCapabilities *)arg1
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

@end
