// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBConsumableXCTestReporter.h"

@interface FBTestRunFailureInfo ()

@end

@implementation FBTestRunFailureInfo

- (instancetype)initWithMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _message = message;
  _file = file;
  _line = line;

  return self;
}

@end

@implementation FBTestRunTestActivity

- (instancetype)initWithTitle:(NSString *)title duration:(NSTimeInterval)duration uuid:(NSString *)uuid
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _title = title;
  _duration = duration;
  _uuid = uuid;

  return self;
}

@end

@interface FBTestRunUpdate ()

@property (nonatomic, strong, nullable, readwrite) FBTestRunFailureInfo *failureInfo;
@property (nonatomic, assign, readwrite) NSTimeInterval duration;
@property (nonatomic, assign, readwrite) BOOL passed;
@property (nonatomic, assign, readwrite) BOOL crashed;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *mutableLogs;
@property (nonatomic, strong, readonly) NSMutableArray<FBTestRunTestActivity *> *mutableActivityLogs;

@end

@implementation FBTestRunUpdate

- (instancetype)initWithBundleName:(NSString *)bundleName className:(NSString *)className methodName:(NSString *)methodName duration:(NSTimeInterval)duration passed:(BOOL)passed crashed:(BOOL)crashed failureInfo:(FBTestRunFailureInfo *)failureInfo
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bundleName = bundleName;
  _className = className;
  _methodName = methodName;
  _duration = duration;
  _passed = passed;
  _crashed = crashed;
  _failureInfo = failureInfo;
  _mutableLogs = NSMutableArray.array;
  _mutableActivityLogs = NSMutableArray.array;

  return self;
}

- (NSArray<NSString *> *)logs
{
  return [self.mutableLogs copy];
}

- (NSArray<FBTestRunTestActivity *> *)activityLogs
{
  return [self.mutableActivityLogs copy];
}

@end

@interface FBConsumableXCTestReporter ()

@property (nonatomic, strong, readonly) NSMutableArray<FBTestRunUpdate *> *finishedTests;

@property (nonatomic, strong, nullable, readwrite) FBTestRunUpdate *currentTest;
@property (nonatomic, copy, nullable, readwrite) NSString *currentBundleName;
@property (nonatomic, copy, nullable, readwrite) NSString *globalErrorMessage;

@end

@implementation FBConsumableXCTestReporter

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _finishedTests = [NSMutableArray array];

  return self;
}

- (NSArray<FBTestRunUpdate *> *)consumeCurrentResults
{
  @synchronized (self) {
    if (_globalErrorMessage) {
      FBTestRunUpdate *testRunInfo = [[FBTestRunUpdate alloc]
        initWithBundleName:nil
        className:nil
        methodName:nil
        duration:0.0
        passed:NO
        crashed:NO
        failureInfo:[[FBTestRunFailureInfo alloc] initWithMessage:_globalErrorMessage file:nil line:0]];
      return @[testRunInfo];
    }
    NSArray<FBTestRunUpdate *> *currentResults = self.finishedTests.mutableCopy;
    [self.finishedTests removeAllObjects];
    return currentResults;
  }
}

- (void)testPlanDidFailWithMessage:(NSString *)message
{
  @synchronized (self) {
    self.globalErrorMessage = message;
  }
}

- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  @synchronized (self) {
    self.currentTest.failureInfo = [[FBTestRunFailureInfo alloc] initWithMessage:message file:file line:line];
  }
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  @synchronized (self) {
    [self testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration logs:nil];
  }
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{
  @synchronized (self) {
    self.currentTest.passed = (status == FBTestReportStatusPassed);
    self.currentTest.duration = duration;
    [self.currentTest.mutableLogs addObjectsFromArray:logs];
    [self.finishedTests addObject:self.currentTest];
  }
}

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  @synchronized (self) {
    self.currentTest = [[FBTestRunUpdate alloc]
      initWithBundleName:self.currentBundleName
      className:testClass
      methodName:method
      duration:0.0
      passed:NO
      crashed:NO
      failureInfo:nil];
  }
}

- (void)testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity
{
  @synchronized (self) {
    FBTestRunTestActivity *testActivity = [[FBTestRunTestActivity alloc] initWithTitle:activity.title duration:activity.duration uuid:activity.uuid.UUIDString];
    [self.currentTest.mutableActivityLogs addObject:testActivity];
  }
}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  @synchronized (self) {
    self.currentBundleName = testSuite;
  }
}

- (void)didCrashDuringTest:(NSError *)error
{
  @synchronized (self) {
    // The test bundle can crash before any test has started.
    FBTestRunUpdate *currentTest = self.currentTest;
    if (!currentTest){
      return;
    }
    currentTest.passed = NO;
    currentTest.crashed = YES;
    currentTest.failureInfo = [[FBTestRunFailureInfo alloc] initWithMessage:error.description file:nil line:0];
    [self.finishedTests addObject:currentTest];
  }
}

#pragma mark - Unused

- (BOOL)printReportWithError:(NSError **)error
{
  return NO;
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{
}

- (void)testHadOutput:(NSString *)output
{
}

- (void)didFinishExecutingTestPlan
{
}

- (void)debuggerAttached
{
}

- (void)didBeginExecutingTestPlan
{
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
}

- (void)handleExternalEvent:(NSString *)event
{
}

@end
