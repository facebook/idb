/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBJSONTestReporter.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

static inline NSString *FBFullyFormattedXCTestName(NSString *className, NSString *methodName);

@interface FBJSONTestReporter ()

@property (nonatomic, strong, readonly) id<FBDataConsumer> dataConsumer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, readonly) NSString *testBundlePath;
@property (nonatomic, copy, readonly) NSString *testType;
@property (nonatomic, copy, readonly) NSMutableArray<NSDictionary<NSString *, id> *> *events;
@property (nonatomic, copy, readonly) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary<NSString *, id> *> *> *xctestNameExceptionsMapping;
@property (nonatomic, copy, readonly) NSMutableArray<NSString *> *pendingTestOutput;

@property (nonatomic, copy, readwrite) NSString *currentTestName;
@property (nonatomic, assign, readwrite) BOOL started;
@property (nonatomic, assign, readwrite) BOOL finished;

@end

@implementation FBJSONTestReporter

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath testType:(NSString *)testType logger:(id<FBControlCoreLogger>)logger dataConsumer:(id<FBDataConsumer>)dataConsumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dataConsumer = dataConsumer;
  _logger = logger;
  _testBundlePath = testBundlePath;
  _testType = testType;
  _xctestNameExceptionsMapping = [NSMutableDictionary dictionary];
  _pendingTestOutput = [NSMutableArray array];

  _currentTestName = nil;
  _started = NO;
  _finished = NO;

  return self;
}

- (BOOL)printReportWithError:(NSError **)error
{
  if (!_started) {
    return [[FBXCTestError describe:[self noStartOfTestPlanErrorMessage]] failBool:error];
  }
  if (!_finished) {
    NSString *errorMessage = @"No didFinishExecutingTestPlan event was received, the test bundle has likely crashed.";
    if (_currentTestName) {
      errorMessage = [errorMessage stringByAppendingString:@". Crash occurred while this test was running: "];
      errorMessage = [errorMessage stringByAppendingString:_currentTestName];
    }
    [self printEvent:[FBJSONTestReporter createOCUnitEndEvent:self.testType testBundlePath:self.testBundlePath message:errorMessage success:NO]];
    return [[FBXCTestError describe:errorMessage] failBool:error];
  }
  [self.dataConsumer consumeEndOfFile];
  return YES;
}

- (void)printEvent:(NSDictionary *)event
{
  NSMutableDictionary *timestamped = event.mutableCopy;
  if (!timestamped[@"timestamp"]) {
    timestamped[@"timestamp"] = @(NSDate.date.timeIntervalSince1970);
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:timestamped options:0 error:nil];
  [self.dataConsumer consumeData:data];
  [self.dataConsumer consumeData:[NSData dataWithBytes:"\n" length:1]];
}

#pragma mark FBXCTestReporter

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{
  [self printEvent:[FBJSONTestReporter waitingForDebuggerEvent:pid]];
}

- (void)debuggerAttached
{
  [self printEvent:[FBJSONTestReporter debuggerAttachedEvent]];
}

- (void)didBeginExecutingTestPlan
{
  _started = YES;
  [self printEvent:[FBJSONTestReporter createOCUnitBeginEvent:self.testType testBundlePath:self.testBundlePath]];
}

- (void)didFinishExecutingTestPlan
{
  if (_started) {
    [self printEvent:[FBJSONTestReporter createOCUnitEndEvent:self.testType testBundlePath:self.testBundlePath message:nil success:YES]];
  } else {
    [self printEvent:[FBJSONTestReporter createOCUnitBeginEvent:self.testType testBundlePath:self.testBundlePath]];
    NSString *errorMessage = [self noStartOfTestPlanErrorMessage];
    [self printEvent:[FBJSONTestReporter createOCUnitEndEvent:self.testType testBundlePath:self.testBundlePath message:errorMessage success:NO]];
  }
  _finished = YES;
}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  [self printEvent:[FBJSONTestReporter beginTestSuiteEvent:testSuite]];
}

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  _currentTestName = xctestName;
  self.xctestNameExceptionsMapping[xctestName] = [NSMutableArray array];
  [self printEvent:[FBJSONTestReporter beginTestCaseEvent:testClass testMethod:method]];
}

- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  [self.xctestNameExceptionsMapping[xctestName] addObject:[FBJSONTestReporter exceptionEvent:message file:file line:line]];
}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{
  _currentTestName = nil;
  NSDictionary<NSString *, id> *event = [FBJSONTestReporter
    testCaseDidFinishForTestClass:testClass
    method:method
    status:status
    duration:duration
    pendingTestOutput:self.pendingTestOutput
    xctestNameExceptionsMapping:self.xctestNameExceptionsMapping];
  [self printEvent:event];
  [self.pendingTestOutput removeAllObjects];
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  [self printEvent:[FBJSONTestReporter finishedEventFromSummary:summary]];
}

- (void)didRecordVideoAtPath:(nonnull NSString *)videoRecordingPath
{
  [self printEvent:@{
    @"event" : @"video-recording-finished",
    @"videoRecordingPath" : videoRecordingPath,
  }];
}

- (void)didSaveOSLogAtPath:(nonnull NSString *)osLogPath
{
  [self printEvent:@{
    @"event" : @"os-log-saved",
    @"osLogPath" : osLogPath,
  }];
}

- (void)didCopiedTestArtifact:(nonnull NSString *)testArtifactFilename toPath:(nonnull NSString *)path
{
  [self printEvent:@{
    @"event" : @"copy-test-artifact",
    @"test_artifact_file_name" : testArtifactFilename,
    @"path" : path,
  }];
}

- (void)testHadOutput:(NSString *)output
{
  [self.pendingTestOutput addObject:output];
  [self printEvent:[FBJSONTestReporter testOutputEvent:output]];
}

- (void)handleExternalEvent:(NSString *)line
{
  if (line.length == 0) {
    return;
  }
  NSError *error = nil;
  NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
  if (event == nil) {
    [self.logger logFormat:@"Received unexpected output from otest-shim:\n%@", line];
  }
  if ([event[@"event"] isEqualToString:@"end-test"]) {
    NSMutableDictionary *mutableEvent = event.mutableCopy;
    mutableEvent[@"output"] = [self.pendingTestOutput componentsJoinedByString:@""];
    event = mutableEvent.copy;
    [self.pendingTestOutput removeAllObjects];
  }
  [self.events addObject:event];
}

- (void)appUnderTestExited
{
}


#pragma mark Event Synthesis

- (NSString *)noStartOfTestPlanErrorMessage
{
  NSString *errorMessage = @"No didBeginExecutingTestPlan event was received.";
  if (_currentTestName) {
    errorMessage = [errorMessage stringByAppendingString:@". However a test was running: "];
    errorMessage = [errorMessage stringByAppendingString:_currentTestName];
  }
  return errorMessage;
}

+ (NSDictionary<NSString *, id> *)exceptionEvent:(NSString *)reason file:(NSString *)file line:(NSUInteger)line
{
  return @{
    @"lineNumber" : @(line),
    @"filePathInProject" : file,
    @"reason" : reason,
  };
}

+ (NSDictionary<NSString *, id> *)beginTestCaseEvent:(NSString *)testClass testMethod:(NSString *)method
{
  return @{
    @"event" : @"begin-test",
    @"className" : testClass,
    @"methodName" : method,
    @"test" : FBFullyFormattedXCTestName(testClass, method),
  };
}

+ (NSDictionary<NSString *, id> *)beginTestSuiteEvent:(NSString *)testSuite
{
  return @{
    @"event" : @"begin-test-suite",
    @"suite" : testSuite,
  };
}

+ (NSDictionary<NSString *, id> *)testOutputEvent:(NSString *)output
{
  return @{
    @"event": @"test-output",
    @"output": output,
  };
}

+ (NSDictionary<NSString *, id> *)waitingForDebuggerEvent:(pid_t)pid
{
  return @{
    @"event": @"begin-status",
    @"pid": @(pid),
    @"level": @"Info",
    @"message": [NSString stringWithFormat:@"Tests waiting for debugger. To debug run: lldb -p %@", @(pid)],
  };
}

+ (NSDictionary<NSString *, id> *)debuggerAttachedEvent
{
  return @{
    @"event": @"end-status",
    @"level": @"Info",
    @"message": @"Debugger attached",
  };
}

+ (NSDictionary<NSString *, id> *)createOCUnitBeginEvent:(NSString *)testType testBundlePath:(NSString *)testBundlePath
{
  return @{
    @"event" : @"begin-ocunit",
    @"testType" : testType,
    @"bundleName" : [testBundlePath lastPathComponent],
    @"targetName" : testBundlePath,
  };
}

+ (NSDictionary<NSString *, id> *)createOCUnitEndEvent:(NSString *)testType testBundlePath:(NSString *)testBundlePath message:(NSString *)message success:(BOOL)success
{
  NSMutableDictionary<NSString *, id> *event = [NSMutableDictionary dictionaryWithDictionary:@{
    @"event" : @"end-ocunit",
    @"testType" : testType,
    @"bundleName" : [testBundlePath lastPathComponent],
    @"targetName" : testBundlePath,
    @"succeeded" : success ? @YES : @NO,
  }];
  if (message) {
    event[@"message"] = message;
  }
  return [event copy];
}

+ (NSDictionary<NSString *, id> *)finishedEventFromSummary:(FBTestManagerResultSummary *)summary
{
  return @{
    @"event" : @"end-test-suite",
    @"suite" : summary.testSuite,
    @"testCaseCount" : @(summary.runCount),
    @"totalFailureCount" : @(summary.failureCount),
    @"totalDuration" : @(summary.totalDuration),
    @"unexpectedExceptionCount" : @(summary.unexpected),
    @"testDuration" : @(summary.testDuration)
  };
}

+ (NSDictionary<NSString *, id> *)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method status:(FBTestReportStatus)status duration:(NSTimeInterval)duration pendingTestOutput:(NSArray<NSString *> *)pendingTestOutput xctestNameExceptionsMapping:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)xctestNameExceptionsMapping
{
  NSString *xctestName = FBFullyFormattedXCTestName(testClass, method);
  return @{
    @"event" : @"end-test",
    @"result" : (status == FBTestReportStatusPassed ? @"success" : @"failure"),
    @"output" : [pendingTestOutput componentsJoinedByString:@""],
    @"test" : xctestName,
    @"className" : testClass,
    @"methodName" : method,
    @"succeeded" : (status == FBTestReportStatusPassed ? @YES : @NO),
    @"exceptions" : xctestNameExceptionsMapping[xctestName] ?: @[],
    @"totalDuration" : @(duration),
  };
}

@end

static inline NSString *FBFullyFormattedXCTestName(NSString *className, NSString *methodName)
{
  return [NSString stringWithFormat:@"-[%@ %@]", className, methodName];
}
