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
#import <DTXConnectionServices/DTXSocketTransport.h>
#import <DTXConnectionServices/DTXTransport.h>

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "XCTestBootstrapError.h"

#import "FBTestBundleConnection.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestReporterForwarder.h"
#import "FBXCTestProcess.h"
#import "FBXCTestReporter.h"

const NSInteger FBProtocolVersion = 0x16;
const NSInteger FBProtocolMinimumVersion = 0x8;

@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface>

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, readonly) FBTestReporterForwarder *reporterForwarder;
@property (nonatomic, strong, readonly) NSMutableDictionary *tokenToBundleIDMap;

@end

@implementation FBTestManagerAPIMediator

#pragma mark - Initializers

+ (FBFuture<NSNull *> *)connectAndRunUntilCompletionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerAPIMediator *mediator = [[self alloc] initWithContext:context target:target reporter:reporter logger:logger];
  return [mediator connectAndRunUntilCompletion];
}

- (instancetype)initWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _reporter = reporter;
  _logger = logger;

  _tokenToBundleIDMap = [NSMutableDictionary new];
  _requestQueue = dispatch_queue_create("com.facebook.xctestboostrap.mediator", DISPATCH_QUEUE_PRIORITY_DEFAULT);

  _reporterForwarder = [FBTestReporterForwarder withAPIMediator:self reporter:reporter];

  return self;
}

#pragma mark - NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"TestManager for (%@)",
    self.context
  ];
}

#pragma mark - Private

static const NSTimeInterval DefaultTestTimeout = (60 * 60);  // 1 hour.

- (FBFuture<NSNull *> *)connectAndRunUntilCompletion
{
  id<FBControlCoreLogger> logger = self.logger;
  id<FBXCTestReporter> reporter = self.reporter;
  dispatch_queue_t queue = self.requestQueue;
  NSTimeInterval timeout = self.context.timeout <= 0 ? DefaultTestTimeout : self.context.timeout;

  return [[[self
    startAndRunApplicationTestHost]
    onQueue:queue pop:^(id<FBLaunchedApplication> launchedApplication) {
      return [[[FBTestBundleConnection
        connectAndRunBundleToCompletionWithContext:self.context
        target:self.target
        interface:(id)self.reporterForwarder
        testHostApplication:launchedApplication
        requestQueue:self.requestQueue
        logger:logger]
        onQueue:queue fmap:^(NSNull *_) {
          // The bundle has disconnected at this point, but we also need to wait for the application to terminate
          return launchedApplication.applicationTerminated;
        }]
        onQueue:queue timeout:timeout handler:^{
          // The timeout is applied to the lifecycle of the entire application.
          [logger logFormat:@"Timed out after %f, attempting stack sample", timeout];
          return [FBXCTestProcess performSampleStackshotOnProcessIdentifier:launchedApplication.processIdentifier forTimeout:timeout queue:queue logger:logger];
        }];
    }]
    onQueue:queue chain:^(FBFuture<NSNull *> *future) {
      [reporter processUnderTestDidExit];

      NSError *error = future.error;
      if (error) {
        [logger logFormat:@"Test Execution finished in error %@", error];
        [reporter didCrashDuringTest:error];
      }
      return future;
    }];
}

- (FBFutureContext<id<FBLaunchedApplication>> *)startAndRunApplicationTestHost
{
  return [[self.target
    launchApplication:self.context.testHostLaunchConfiguration]
    onQueue:self.target.workQueue contextualTeardown:^(id<FBLaunchedApplication> launchedApplication, FBFutureState _) {
      return [launchedApplication.applicationTerminated cancel];
    }];
}

- (FBFuture<id<FBLaunchedApplication>> *)installAndLaunchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path
{
  if (!path) {
    return [[FBControlCoreError
      describeFormat:@"Could not install App-Under-Test %@ as it is not installed and no path was provided", configuration]
      failFuture];
  }
  return [[[[self.target
    isApplicationInstalledWithBundleID:configuration.bundleID]
    onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> *(NSNumber *isInstalled) {
      if (!isInstalled.boolValue) {
        return FBFuture.empty;
      }
      return [self.target uninstallApplicationWithBundleID:configuration.bundleID];
    }]
    onQueue:self.target.workQueue fmap:^(NSNull *_) {
      return [self.target installApplicationWithPath:path];
    }]
    onQueue:self.target.workQueue fmap:^(NSNull *_) {
      return [self.target launchApplication:configuration];
    }];
}

- (FBFuture<id<FBLaunchedApplication>> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path
{
  // Check if path points to installed app
  return [[self.target
    installedApplicationWithBundleID:configuration.bundleID]
    onQueue:self.target.workQueue chain:^(FBFuture<FBInstalledApplication *> *future) {
      FBInstalledApplication *app = future.result;
      if (app && [app.bundle.path isEqualToString:path]) {
        return [self.target launchApplication:configuration];
      }
      return [self installAndLaunchApplication:configuration atPath:path];
    }];
}

#pragma mark - XCTestManager_IDEInterface protocol

#pragma mark Process Launch Delegation

- (id)_XCT_launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment
{
  [self.logger logFormat:@"Test process requested process launch with bundleID %@", bundleID];
  NSMutableDictionary<NSString *, NSString *> *targetEnvironment = @{}.mutableCopy;
  [targetEnvironment addEntriesFromDictionary:self.context.testedApplicationAdditionalEnvironment];
  [targetEnvironment addEntriesFromDictionary:environment];

  FBProcessIO *processIO = [[FBProcessIO alloc]
    initWithStdIn:nil
    stdOut:[FBProcessOutput outputForLogger:self.logger]
    stdErr:[FBProcessOutput outputForLogger:self.logger]];

  DTXRemoteInvocationReceipt *receipt = [objc_lookUpClass("DTXRemoteInvocationReceipt") new];
  FBApplicationLaunchConfiguration *launch = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:bundleID
    bundleName:bundleID
    arguments:arguments
    environment:targetEnvironment
    waitForDebugger:NO
    io:processIO
    launchMode:FBApplicationLaunchModeFailIfRunning];
  id token = @(receipt.hash);

  [[self
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
  [self.logger log:@"Started initilizing for UI testing."];
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
  [self.logger logFormat:@"Test Suite %@ started", tests];
  if (tests.length == 0) {
    NSError *error = [[[[XCTestBootstrapError
      describe:@"Test reported a suite with nil or empty identifier. This is unsupported."]
      inDomain:@"IDETestOperationsObserverErrorDomain"]
      code:0x9]
      build];
    [self.logger logFormat:@"%@", error];
  }

  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Started"];
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Ended"];
  return nil;
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.logger logFormat:@"Test Case %@/%@ did start", testClass, method];
  return nil;
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
  [self.logger logFormat:@"Test Case %@/%@ did fail: %@", testClass, method, message];
  return nil;
}

- (id)_XCT_logDebugMessage:(NSString *)debugMessage
{
  [self.logger log:[debugMessage stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
  return nil;
}

- (id)_XCT_logMessage:(NSString *)message
{
  return nil;
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  [self.logger logFormat:@"Test Case %@/%@ did finish (%@)", testClass, method, statusString];
  return nil;
}

- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 withFailures:(NSNumber *)arg4 unexpected:(NSNumber *)arg5 testDuration:(NSNumber *)arg6 totalDuration:(NSNumber *)arg7
{
  [self.logger logFormat:@"Test Suite Did Finish %@", arg1];
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
