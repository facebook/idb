/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerAPIMediator.h"

#import <XCTestPrivate/XCTestDriverInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_DaemonConnectionInterface-Protocol.h>
#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>

#import <XCTestPrivate/XCTMessagingChannel_RunnerToIDE-Protocol.h>

#import <XCTestPrivate/XCTTestIdentifier.h>
#import <XCTestPrivate/XCTIssue.h>

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
#import "FBTestReporterAdapter.h"
#import "FBXCTestProcess.h"
#import "FBXCTestReporter.h"


@interface FBTestManagerAPIMediator () <XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE>

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) id<FBiOSTarget, FBXCTestExtendedCommands> target;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) dispatch_queue_t requestQueue;
@property (nonatomic, strong, readonly) FBTestReporterAdapter *reporterAdapter;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, id<FBLaunchedApplication>> *tokenToLaunchedAppMap;

@end

@implementation FBTestManagerAPIMediator

#pragma mark - Initializers

+ (FBFuture<NSNull *> *)connectAndRunUntilCompletionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget, FBXCTestExtendedCommands>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerAPIMediator *mediator = [[self alloc] initWithContext:context target:target reporter:reporter logger:logger];
  return [mediator connectAndRunUntilCompletion];
}

- (instancetype)initWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget, FBXCTestExtendedCommands>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _context = context;
  _target = target;
  _reporter = reporter;
  _logger = logger;

  _tokenToLaunchedAppMap = [NSMutableDictionary new];
  _requestQueue = dispatch_queue_create("com.facebook.xctestboostrap.mediator", DISPATCH_QUEUE_PRIORITY_DEFAULT);

  _reporterAdapter = [FBTestReporterAdapter withReporter:reporter];

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

- (FBFuture<NSNull *> *)terminateSpawnedProcesses
{

  NSArray<id<FBLaunchedApplication>> *appsToKill = [self.tokenToLaunchedAppMap allValues];
  [self.tokenToLaunchedAppMap removeAllObjects];

  if (appsToKill.count > 0) {
    [self.logger logFormat:@"Terminating processes spawned due to test bundle requests: %@", [FBCollectionInformation oneLineDescriptionFromArray:appsToKill]];

    NSMutableArray<FBFuture *> *futuresToWait = [NSMutableArray arrayWithCapacity:appsToKill.count];
    for (id<FBLaunchedApplication> app in appsToKill) {
      [futuresToWait addObject:[self.target killApplicationWithBundleID:app.bundleID]];
    }
    return [FBFuture futureWithFutures:futuresToWait.copy];
  }

  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)connectAndRunUntilCompletion
{
  id<FBControlCoreLogger> logger = self.logger;
  id<FBXCTestReporter> reporter = self.reporter;
  dispatch_queue_t queue = self.requestQueue;
  NSTimeInterval timeout = self.context.timeout <= 0 ? DefaultTestTimeout : self.context.timeout;

  return [[[self
    startAndRunApplicationTestHost]
    onQueue:queue pop:^(id<FBLaunchedApplication> launchedApplication) {
      bool waitForDebugger = self.context.testHostLaunchConfiguration.waitForDebugger;
      FBFuture *future = FBFuture.empty;
      if (waitForDebugger) {
        [reporter processWaitingForDebuggerWithProcessIdentifier:launchedApplication.processIdentifier];
        future = [FBProcessFetcher waitForDebuggerToAttachAndContinueFor:launchedApplication.processIdentifier];
      }

      return [future onQueue:queue fmap:^(id _) {
        return [self runUntilCompletion:launchedApplication logger:logger queue:queue timeout:timeout];
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

- (FBFuture<NSNull *> *)runUntilCompletion:(id<FBLaunchedApplication>)launchedApplication logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout
{
  return [[[FBTestBundleConnection
    connectAndRunBundleToCompletionWithContext:self.context
    target:self.target
    interface:self
    testHostApplication:launchedApplication
    requestQueue:self.requestQueue
    logger:logger]
    onQueue:queue fmap:^(NSNull *_) {
      // The bundle has disconnected at this point, but we also need to terminate any processes
      // spawned through `_XCT_launchProcessWithPath`and wait for the host application to terminate
      return [[[self terminateSpawnedProcesses] chainReplace:launchedApplication.applicationTerminated] cancel];
    }]
    onQueue:queue timeout:timeout handler:^{
      // The timeout is applied to the lifecycle of the entire application.
      [logger logFormat:@"Timed out after %f, attempting stack sample", timeout];
      return [[[FBProcessFetcher
        performSampleStackshotForProcessIdentifier:launchedApplication.processIdentifier
        queue:queue]
      onQueue:queue fmap:^FBFuture<id> *(NSString *stackshot) {
        return [[FBXCTestError
          describeFormat:@"Waited %f seconds for process %d to terminate, but the host application process stalled: %@", timeout, launchedApplication.processIdentifier, stackshot]
          failFuture];
      }]
      onQueue:queue chain:^FBFuture *(FBFuture *future) {
        return [[self terminateSpawnedProcesses] chainReplace:future];
      }];
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
  return [[[[self
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

- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID
{
  return [[self.target
    installedApplicationWithBundleID:bundleID]
    onQueue:self.target.asyncQueue chain:^(FBFuture<FBInstalledApplication *> *future) {
      return [FBFuture futureWithResult:(future.state == FBFutureStateDone ? @YES : @NO)];
    }];
}

#pragma mark - XCTestManager_IDEInterface protocol

#pragma mark Process Launch Delegation (UI Tests)

/// This callback is called when the UI tests call `-[XCUIApplication launch]` to launch the target app
/// It should return an NSNumber containing an unique identifier to this process, the `token`
/// This `token` will be used later on for further requests ralated to this process
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
    onQueue:self.target.workQueue notifyOfCompletion:^(FBFuture<id<FBLaunchedApplication>> *future) {
      NSError *innerError = future.error;
      if (innerError) {
        [receipt invokeCompletionWithReturnValue:nil error:innerError];
      } else {
        self.tokenToLaunchedAppMap[token] = future.result;
        [receipt invokeCompletionWithReturnValue:token error:nil];
      }
    }];

  return receipt;
}

/// After _XCT_launchProcessWithPath:bundleID:arguments:environmentVariables: is called,
/// this method will be called to check on wherer the process has already been launched or not
/// return should be 0 or 1.
///
/// If 0 is returned, `_XCT_getProgressForLaunch:` will be called again until 1 is returned
///
/// Since we only invoke `_XCT_launchProcessWithPath:bundleID:arguments:environmentVariables:`'s receipt
/// completion after the process is launched, we just return 1 (because the process is already launched)
- (id)_XCT_getProgressForLaunch:(id)token
{
  [self.logger logFormat:@"Test process requested launch process status with token %@", token];
  DTXRemoteInvocationReceipt *receipt = [objc_lookUpClass("DTXRemoteInvocationReceipt") new];
  [receipt invokeCompletionWithReturnValue:@1 error:nil];
  return receipt;
}

/// Called whenever the target process needs to be killed, for instance when `-[XCUIApplication launch]`
/// is called to launch the target app for the next test.
///
/// `token` identifies which process should be terminated. It contains the value that
/// `_XCT_launchProcessWithPath:bundleID:arguments:environmentVariables:` defined
///
/// This method doesn't seem to be called when all the tests finish execution.
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
    NSString *bundleID = self.tokenToLaunchedAppMap[token].bundleID;
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

- (id)_XCT_testSuite:(NSString *)testSuite didStartAt:(NSString *)time
{
  [self.logger logFormat:@"Test Suite %@ started", testSuite];
  if (testSuite.length == 0) {
    NSError *error = [[[[XCTestBootstrapError
      describe:@"Test reported a suite with nil or empty identifier. This is unsupported."]
      inDomain:@"IDETestOperationsObserverErrorDomain"]
      code:0x9]
      build];
    [self.logger logFormat:@"%@", error];
  }

  [self.reporterAdapter _XCT_testSuite:testSuite didStartAt:time];

  return nil;
}

- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)suiteIdentifier didStartAt:(NSString *)time {
  [self _XCT_testSuite:[suiteIdentifier _identifierString] didStartAt:time]; // for some reason the property accessor (-[XCTTestIdentifier identifierString]) crashes
  return nil;
}


- (id)_XCT_didBeginExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Started"];
  [self.reporterAdapter _XCT_didBeginExecutingTestPlan];
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.logger logFormat:@"Test Plan Ended"];
  [self.reporterAdapter _XCT_didFinishExecutingTestPlan];
  return nil;
}

- (id)_XCT_testBundleReadyWithProtocolVersion:(NSNumber *)protocolVersion minimumVersion:(NSNumber *)minimumVersion
{
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.logger logFormat:@"Test Case %@/%@ did start", testClass, method];
  [self.reporterAdapter _XCT_testCaseDidStartForTestClass:testClass method:method];
  return nil;
}

- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1 testCaseRunConfiguration:(XCTestCaseRunConfiguration *)arg2 
{
    [self.logger logFormat:@"Test Case %@/%@ did start", arg1.firstComponent, arg1.lastComponent];
    [self.reporterAdapter _XCT_testCaseDidStartForTestClass:arg1.firstComponent method:arg1.lastComponent];
    return nil;
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didRecordIssue:(XCTIssue *)arg2 {
  [self.logger logFormat:@"Test Case %@/%@ did fail: %@", arg1.firstComponent, arg1.lastComponent, arg2.detailedDescription ?: arg2.compactDescription];
  return [self.reporterAdapter _XCT_testCaseDidFailForTestClass:arg1.firstComponent method:arg1.lastComponent
                                                    withMessage:arg2.compactDescription
                                                           file:arg2.sourceCodeContext.location.fileURL.absoluteString
                                                           line:@(arg2.sourceCodeContext.location.lineNumber)];
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
  [self.logger logFormat:@"Test Case %@/%@ did fail: %@", testClass, method, message];
  [self.reporterAdapter _XCT_testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line];
  return nil;
}

- (id)_XCT_logDebugMessage:(NSString *)debugMessage
{
  [self.logger log:[debugMessage stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
  return nil;
}

- (id)_XCT_logMessage:(NSString *)message
{
  [self.logger logFormat:@"_XCT_logMessage: %@", message];
  return nil;
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  [self.logger logFormat:@"Test Case %@/%@ did finish (%@)", testClass, method, statusString];
  [self.reporterAdapter _XCT_testCaseDidFinishForTestClass:testClass method:method withStatus:statusString duration:duration];
  return nil;
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)identifier didFinishWithStatus:(NSString *)statusString duration:(NSNumber *)duration {
  return [self _XCT_testCaseDidFinishForTestClass:identifier.firstComponent method:identifier.lastComponent withStatus:statusString duration:duration];
}


- (id)_XCT_testSuite:(NSString *)testSuite didFinishAt:(NSString *)time runCount:(NSNumber *)runCount withFailures:(NSNumber *)failures unexpected:(NSNumber *)unexpected testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration
{
  [self.logger logFormat:@"Test Suite Did Finish %@", testSuite];
  [self.reporterAdapter _XCT_testSuite:testSuite didFinishAt:time runCount:runCount withFailures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
  return nil;
}

- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 skipCount:(NSNumber *)arg4 failureCount:(NSNumber *)arg5 expectedFailureCount:(NSNumber *)arg6 uncaughtExceptionCount:(NSNumber *)arg7 testDuration:(NSNumber *)arg8 totalDuration:(NSNumber *)arg9 {
  // do nothing as the values reported by the legacy method _XCT_testSuite:didFinishAt:runCount:withFailures:unexpected:testDuration:
  // are ignored on IDBXCTestReporter
  return nil;
}


- (id)_XCT_testCase:(NSString *)testCase method:(NSString *)method didFinishActivity:(XCActivityRecord *)activity
{
  [self.reporterAdapter _XCT_testCase:testCase method:method didFinishActivity:activity];
  return nil;
}

- (id)_XCT_testCase:(NSString *)testCase method:(NSString *)method willStartActivity:(XCActivityRecord *)activity
{
  [self.reporterAdapter _XCT_testCase:testCase method:method willStartActivity:activity];
  return nil;
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didFinishActivity:(XCActivityRecord *)arg2 {
  [self.reporterAdapter _XCT_testCase:arg1.firstComponent method:arg1.lastComponent didFinishActivity:arg2];
  return nil;
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 willStartActivity:(XCActivityRecord *)arg2 {
  [self.reporterAdapter _XCT_testCase:arg1.firstComponent method:arg1.lastComponent willStartActivity:arg2];
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

- (id)_XCT_testCaseWasSkippedForTestClass:(NSString *)arg1 method:(NSString *)arg2 withMessage:(NSString *)arg3 file:(NSString *)arg4 line:(NSNumber *)arg5 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 skipCount:(NSNumber *)arg4 failureCount:(NSNumber *)arg5 expectedFailureCount:(NSNumber *)arg6 uncaughtExceptionCount:(NSNumber *)arg7 testDuration:(NSNumber *)arg8 totalDuration:(NSNumber *)arg9 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 skipCount:(NSNumber *)arg4 failureCount:(NSNumber *)arg5 unexpectedFailureCount:(NSNumber *)arg6 testDuration:(NSNumber *)arg7 totalDuration:(NSNumber *)arg8 {
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

- (id)_XCT_didFailToBootstrapWithError:(NSError *)arg1 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_reportTestWithIdentifier:(XCTTestIdentifier *)arg1 didExceedExecutionTimeAllowance:(NSNumber *)arg2 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testCaseDidStartWithIdentifier:(XCTTestIdentifier *)arg1 iteration:(NSNumber *)arg2 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didRecordExpectedFailure:(XCTExpectedFailure *)arg2 {
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didStallOnMainThreadInFile:(NSString *)arg2 line:(NSNumber *)arg3 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 wasSkippedWithMessage:(NSString *)arg2 sourceCodeContext:(XCTSourceCodeContext *)arg3 {
  return [self handleUnimplementedXCTRequest:_cmd];
}


- (id)_XCT_testSuiteWithIdentifier:(XCTTestIdentifier *)arg1 didRecordIssue:(XCTIssue *)arg2 {
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

- (id)_XCT_reportSelfDiagnosisIssue:(NSString *)arg1 description:(NSString *)arg2 {
  return [self handleUnimplementedXCTRequest:_cmd];
}

- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didMeasureMetric:(NSDictionary *)arg2 file:(NSString *)arg3 line:(NSNumber *)arg4 {
  return [self handleUnimplementedXCTRequest:_cmd];
}

@end
