/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBJSONTestReporter.h"

#import "FBXCTestError.h"

static inline NSString *FBFullyFormattedXCTestName(NSString *className, NSString *methodName);

@interface FBJSONTestReporter ()
@property (nonatomic, copy, readwrite) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *xctestNameExceptionsMapping;
@property (nonatomic, copy, readwrite) NSString *testBundlePath;
@property (nonatomic, copy, readwrite) NSString *testType;
@property (nonatomic, copy, readwrite) NSMutableArray<NSDictionary *> *events;
@property (nonatomic, copy, readwrite) NSMutableArray<NSString *> *pendingTestOutput;
@property (nonatomic, copy, readwrite) NSString *currentTestName;
@property (nonatomic, assign, readwrite) BOOL finished;
@end

@implementation FBJSONTestReporter

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath testType:(NSString *)testType
{
  self = [super init];
  if (self) {
    _xctestNameExceptionsMapping = [NSMutableDictionary dictionary];
    _testBundlePath = testBundlePath;
    _testType = testType;
    _events = [NSMutableArray array];
    _pendingTestOutput = [NSMutableArray array];
    _currentTestName = nil;
    _finished = NO;
  }
  return self;
}

- (BOOL)printReportWithError:(NSError **)error
{
  if (!_finished) {
    NSString *errorMessage = @"No end-ocunit event was received, the test bundle has likely crashed";
    if (_currentTestName) {
      errorMessage = [errorMessage stringByAppendingString:@". Crash occurred while this test was running: "];
      errorMessage = [errorMessage stringByAppendingString:_currentTestName];
    }
    [self printEvent:[self createOCUnitBeginEvent]];
    [self printEvent:[self createOCUnitEndEventWithMessage:errorMessage success:NO]];
    return [[FBXCTestError describe:errorMessage] failBool:error];
  }
  for (NSDictionary *event in _events) {
    [self printEvent:event];
  }
  return YES;
}

- (void)storeEvent:(NSDictionary *)dictionary
{
  NSMutableDictionary *mDictionary = dictionary.mutableCopy;
  mDictionary[@"timestamp"] = @([NSDate date].timeIntervalSince1970);
  [_events addObject:mDictionary.copy];
}

- (void)printEvent:(NSDictionary *)event
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
  [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
  [[NSFileHandle fileHandleWithStandardOutput] writeData:[NSData dataWithBytes:"\n" length:1]];
}

- (NSDictionary *)createOCUnitBeginEvent
{
  return @{
           @"event" : @"begin-ocunit",
           @"testType" : _testType,
           @"bundleName" : [_testBundlePath lastPathComponent],
           @"targetName" : _testBundlePath,
           };
}

- (NSDictionary *)createOCUnitEndEventWithMessage:(NSString *)message success:(BOOL)success
{
  NSMutableDictionary<NSString *, id> *event = [NSMutableDictionary dictionary];
  [event addEntriesFromDictionary:@{
    @"event" : @"end-ocunit",
    @"testType" : _testType,
    @"bundleName" : [_testBundlePath lastPathComponent],
    @"targetName" : _testBundlePath,
    @"succeeded" : success ? @YES : @NO,
  }];
  if (message) {
    event[@"message"] = message;
  }
  return [event copy];
}

#pragma mark FBXCTestReporter

- (void)didBeginExecutingTestPlan
{
  [self storeEvent:[self createOCUnitBeginEvent]];
}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  [self storeEvent:@{
    @"event" : @"begin-test-suite",
    @"suite" : testSuite,
  }];
}

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  _currentTestName = xctestName;
  self.xctestNameExceptionsMapping[xctestName] = [NSMutableArray array];
  [self storeEvent:@{
    @"event" : @"begin-test",
    @"className" : testClass,
    @"methodName" : method,
    @"test" : FBFullyFormattedXCTestName(testClass, method),
  }];
}

- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  [self.xctestNameExceptionsMapping[xctestName] addObject:@{
    @"lineNumber" : @(line),
    @"filePathInProject" : file,
    @"reason" : message,
  }];
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  _currentTestName = nil;
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  [self storeEvent:@{
    @"event" : @"end-test",
    @"result" : (status == FBTestReportStatusPassed ? @"success" : @"failure"),
    @"output" : [self.pendingTestOutput componentsJoinedByString:@""],
    @"test" : FBFullyFormattedXCTestName(testClass, method),
    @"className" : testClass,
    @"methodName" : method,
    @"succeeded" : (status == FBTestReportStatusPassed ? @YES : @NO),
    @"exceptions" : self.xctestNameExceptionsMapping[xctestName] ?: @[],
    @"totalDuration" : @(duration),
  }];
  [self.pendingTestOutput removeAllObjects];
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  [self storeEvent:@{
    @"event" : @"end-test-suite",
    @"suite" : summary.testSuite,
    @"testCaseCount" : @(summary.runCount),
    @"totalFailureCount" : @(summary.failureCount),
    @"totalDuration" : @(summary.totalDuration),
    @"unexpectedExceptionCount" : @(summary.unexpected),
    @"testDuration" : @(summary.testDuration)
  }];
}

- (void)didFinishExecutingTestPlan
{
  _finished = YES;
  [self storeEvent:[self createOCUnitEndEventWithMessage:nil success:YES]];
}

- (void)testHadOutput:(NSString *)output
{
  [self.pendingTestOutput addObject:output];
  [self storeEvent:@{
    @"event": @"test-output",
    @"output": output
  }];
}

- (void)handleExternalEvent:(NSDictionary *)event
{
  if ([event[@"event"] isEqualToString:@"end-test"]) {
    NSMutableDictionary *mutableEvent = event.mutableCopy;
    mutableEvent[@"output"] = [self.pendingTestOutput componentsJoinedByString:@""];
    event = mutableEvent.copy;
    [self.pendingTestOutput removeAllObjects];
  }
  [self.events addObject:event];
}

@end

static inline NSString *FBFullyFormattedXCTestName(NSString *className, NSString *methodName)
{
  return [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
}
