/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestResultBundleParser.h"

int const XCTestOperationTimeoutSecs = 120;

NS_ASSUME_NONNULL_BEGIN

#pragma mark STATIC FUNCTIONS

static inline id readFromDict(NSDictionary *dict, NSString *key, Class klass)
{
  id val = dict[key];
  NSCAssert(val, @"%@ is not present in dict", key);
  val = [val isKindOfClass:klass] ? val : nil;
  NSCAssert(val, @"%@ is not a %@", key, klass);
  return val;
}

static inline NSNumber *readNumberFromDict(NSDictionary *dict, NSString *key)
{
  return readFromDict(dict, key, NSNumber.class);
}

static inline double readDoubleFromDict(NSDictionary *dict, NSString *key)
{
  NSNumber *number = readNumberFromDict(dict, key);
  return [number doubleValue];
}

static inline NSString *readStringFromDict(NSDictionary *dict, NSString *key)
{
  return readFromDict(dict, key, NSString.class);
}

static inline NSArray *readArrayFromDict(NSDictionary *dict, NSString *key)
{
  return readFromDict(dict, key, NSArray.class);
}

static inline NSArray *unwrapValues(NSDictionary<NSString *, NSObject *> *wrapped)
{
  @try {
    return readFromDict(wrapped, @"_values", NSArray.class);
  }
  @catch (id e) {
    return nil;
  }
}

static inline id unwrapValue(NSDictionary<NSString *, NSObject *> *wrapped)
{
  @try {
    return readFromDict(wrapped, @"_value", NSObject.class);
  }
  @catch (id e) {
    return nil;
  }
}

static NSArray *accessAndUnwrapValues(NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *dict, NSString *key, id<FBControlCoreLogger> logger)
{
  NSDictionary<NSString *, NSObject *> *wrapped = dict[key];
  if (wrapped != nil) {
    NSArray *unwrapped = unwrapValues(wrapped);
    if (unwrapped == nil) {
      [logger logFormat:@"Failed to unwrap values for %@ from %@", key, [FBCollectionInformation oneLineDescriptionFromArray:[wrapped allKeys]]];
    }
    return unwrapped;
  } else {
    [logger logFormat:@"%@ does not exist inside %@", key, [FBCollectionInformation oneLineDescriptionFromArray:[dict allKeys]]];
    return nil;
  }
}

static id accessAndUnwrapValue(NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *dict, NSString *key, id<FBControlCoreLogger> logger)
{
  NSDictionary<NSString *, NSObject *> *wrapped = dict[key];
  if (wrapped != nil) {
    id unwrapped = unwrapValue(wrapped);
    if (unwrapped == nil) {
      [logger logFormat:@"Failed to unwrap value for %@ from %@", key, [FBCollectionInformation oneLineDescriptionFromArray:[wrapped allKeys]]];
    }
    return unwrapped;
  } else {
    [logger logFormat:@"%@ does not exist inside %@", key, [FBCollectionInformation oneLineDescriptionFromArray:[dict allKeys]]];
    return nil;
  }
}

static inline NSDate *dateFromString(NSString *date)
{
  // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
  NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
  [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
  return [dateFormatter dateFromString:date];
}

@implementation FBXCTestResultBundleParser

#pragma mark PUBLIC

+ (FBFuture<NSNull *> *)parse:(NSString *)resultBundlePath target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Parsing the result bundle %@", resultBundlePath];

  NSString *testSummariesPath = [resultBundlePath stringByAppendingPathComponent:@"TestSummaries.plist"];
  NSDictionary<NSString *, NSArray *> *results = [NSDictionary dictionaryWithContentsOfFile:testSummariesPath];
  NSString *resultBundleInfoPath = [resultBundlePath stringByAppendingPathComponent:@"Info.plist"];
  NSDictionary<NSString *, NSObject *> *bundleInfo = [NSDictionary dictionaryWithContentsOfFile:resultBundleInfoPath];
  id bundleFormatVersion =[bundleInfo valueForKey:@"version"];

  if (results) {
    [self reportResults:results reporter:reporter];
    [logger logFormat:@"ResultBundlePath: %@", resultBundlePath];
    return FBFuture.empty;
  }
  else if (bundleFormatVersion && [bundleFormatVersion isKindOfClass:NSDictionary.class]) {
    NSNumber *majorVersion = readNumberFromDict(bundleFormatVersion, @"major");
    NSNumber *minorVersion = readNumberFromDict(bundleFormatVersion, @"minor");
    [logger logFormat:@"Test result bundle format version: %@.%@", majorVersion, minorVersion];
    return [[FBXCTestResultToolOperation
      getJSONFrom:resultBundlePath forId:nil queue:target.workQueue logger:logger]
      onQueue:target.workQueue fmap:^(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *actionsInvocationRecord) {
        NSDictionary<NSString *, NSArray *> *actions = actionsInvocationRecord[@"actions"];
        NSArray<NSString *> *ids = [self parseActions:actions logger:logger];
        NSMutableArray<FBFuture *> *operations = NSMutableArray.array;
        for (NSString *bundleObjectId in ids) {
          FBFuture *operation = [[FBXCTestResultToolOperation
            getJSONFrom:resultBundlePath forId:bundleObjectId queue:target.workQueue logger:logger]
            onQueue:target.workQueue doOnResolved:^void (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *xcresults) {
              [logger logFormat:@"Parsing summaries for id %@", bundleObjectId];
              NSArray<NSDictionary *> *summaries = accessAndUnwrapValues(xcresults, @"summaries", logger);
              [self reportSummaries:summaries reporter:reporter queue:target.asyncQueue resultBundlePath:resultBundlePath logger:logger];
              [logger logFormat:@"Done parsing summaries for id %@", bundleObjectId];
            }];
          [operations addObject:operation];
        }
        return [FBFuture futureWithFutures:operations];
      }];
  }
  else {
    [reporter testManagerMediator:nil testPlanDidFailWithMessage:@"No test results were produced"];
    return FBFuture.empty;
  }
}

#pragma mark Private: Legacy XCTest Result Parsing

+ (void)reportResults:(NSDictionary<NSString *, NSArray *> *)results reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert([results isKindOfClass:NSDictionary.class], @"Test results not a NSDictionary");
  NSArray<NSDictionary *> *testTargets = results[@"TestableSummaries"];

  [self reportTargetTests:testTargets reporter:reporter];
}

+ (void)reportTargetTests:(NSArray<NSDictionary *> *)targetTests reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(targetTests, @"targetTests is nil");
  NSAssert([targetTests isKindOfClass:NSArray.class], @"targetTests not a NSArray");

  for (NSDictionary<NSString *, NSObject *> *targetTest in targetTests) {
    [self reportTargetTest:targetTest reporter:reporter];
  }
}

+ (void)reportTargetTest:(NSDictionary<NSString *, NSObject *> *)targetTest reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(targetTest, @"targetTest is nil");
  NSAssert([targetTest isKindOfClass:NSDictionary.class], @"targetTest not a NSDictionary");
  NSString *testBundleName = readStringFromDict(targetTest, @"TestName");

  NSArray<NSDictionary *> *selectedTests = (NSArray<NSDictionary *> *)targetTest[@"Tests"];
  [self reportSelectedTests:selectedTests testBundleName:testBundleName reporter:reporter];
}

+ (void)reportSelectedTests:(NSArray<NSDictionary *> *)selectedTests testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTests, @"selectedTests is nil");
  NSAssert([selectedTests isKindOfClass:NSArray.class], @"selectedTests not a NSArray");

  for (NSDictionary *selectedTest in selectedTests) {
    [self reportSelectedTest:selectedTest testBundleName:testBundleName reporter:reporter];
  }
}

+ (void)reportSelectedTest:(NSDictionary<NSString *, NSObject *> *)selectedTest testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTest, @"selectedTest is nil");
  NSAssert([selectedTest isKindOfClass:NSDictionary.class], @"selectedTest not a NSDictionary");

  NSArray<NSDictionary *> *testTargetXctests = (NSArray<NSDictionary *> *)selectedTest[@"Subtests"];
  [self reportTestTargetXctests:testTargetXctests testBundleName:testBundleName reporter:reporter];
}

+ (void)reportTestTargetXctests:(NSArray<NSDictionary *> *)testTargetXctests testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctests, @"testTargetXctests is nil");
  NSAssert([testTargetXctests isKindOfClass:NSArray.class], @"testTargetXctests not a NSArray");

  for (NSDictionary *testTargetXctest in testTargetXctests) {
    [self reportTestTargetXctest:testTargetXctest testBundleName:testBundleName reporter:reporter];
  }
}

+ (void)reportTestTargetXctest:(NSDictionary<NSString *, NSObject *> *)testTargetXctest testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctest, @"selectedTest is nil");
  NSAssert([testTargetXctest isKindOfClass:NSDictionary.class], @"testTargetXctest not a NSDictionary");

  NSArray *testClasses = (NSArray *)testTargetXctest[@"Subtests"];
  [self reportTestClasses:testClasses testBundleName:testBundleName reporter:reporter];
}

+ (void)reportTestClasses:(NSArray<NSDictionary *> *)testClasses testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testClasses, @"selectedTest is nil");
  NSAssert([testClasses isKindOfClass:NSArray.class], @"testClasses not a NSArray");

  for (NSDictionary *testClass in testClasses) {
    [self reportTestClass:testClass testBundleName:testBundleName reporter:reporter];
  }
}

+ (void)reportTestClass:(NSDictionary<NSString *, NSObject *> *)testClass testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testClass, @"selectedTest is nil");
  NSAssert([testClass isKindOfClass:NSDictionary.class], @"testClass not a NSDictionary");

  NSString *testClassName = readStringFromDict(testClass, @"TestIdentifier");
  NSArray<NSDictionary *> *testMethods = (NSArray<NSDictionary *> *)testClass[@"Subtests"];
  [self reportTestMethods:testMethods testBundleName:testBundleName testClassName:testClassName reporter:reporter];
}

+ (void)reportTestMethods:(NSArray<NSDictionary *> *)testMethods testBundleName:(NSString *)testBundleName testClassName:(NSString *)testClassName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testMethods, @"testMethods is nil");
  NSAssert([testMethods isKindOfClass:NSArray.class], @"testMethods not a NSArray");

  for (NSDictionary *testMethod in testMethods) {
    [self reportTestMethod:testMethod testBundleName:testBundleName testClassName:testClassName reporter:reporter];
  }
}

+ (void)reportTestMethod:(NSDictionary<NSString *, NSObject *> *)testMethod testBundleName:(NSString *)testBundleName testClassName:(NSString *)testClassName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testMethod, @"testMethod is nil");
  NSAssert([testMethod isKindOfClass:NSDictionary.class], @"testMethod not a NSDictionary");

  NSString *testStatus = readStringFromDict(testMethod, @"TestStatus");
  NSString *testMethodName = readStringFromDict(testMethod, @"TestIdentifier");
  NSNumber *duration = readNumberFromDict(testMethod, @"Duration");

  FBTestReportStatus status = FBTestReportStatusUnknown;
  if ([testStatus isEqualToString:@"Success"]) {
    status = FBTestReportStatusPassed;
  }
  if ([testStatus isEqualToString:@"Failure"]) {
    status = FBTestReportStatusFailed;
  }

  NSArray *activitySummaries = readArrayFromDict(testMethod, @"ActivitySummaries");
  NSMutableArray *logs = [self buildTestLogLegacy:activitySummaries
                                   testBundleName:testBundleName
                                    testClassName:testClassName
                                   testMethodName:testMethodName
                                       testPassed:status == FBTestReportStatusPassed
                                         duration:[duration doubleValue]];

  [reporter testManagerMediator:nil testCaseDidStartForTestClass:testClassName method:testMethodName];
  if (status == FBTestReportStatusFailed) {
    NSArray *failureSummaries = readArrayFromDict(testMethod, @"FailureSummaries");
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:testClassName method:testMethodName withMessage:[self buildErrorMessageLegacy:failureSummaries] file:nil line:0];
  }

  if ([reporter respondsToSelector:@selector(testManagerMediator:testCaseDidFinishForTestClass:method:withStatus:duration:logs:)]) {
    [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodName withStatus:status duration:[duration doubleValue] logs:[logs copy]];
  }
  else {
    [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodName withStatus:status duration:[duration doubleValue]];
  }
}

+ (NSMutableArray<NSString *> *)buildTestLogLegacy:(NSArray<NSDictionary *> *)activitySummaries
                                    testBundleName:(NSString *)testBundleName
                                     testClassName:(NSString *)testClassName
                                    testMethodName:(NSString *)testMethodName
                                        testPassed:(BOOL)testPassed
                                          duration:(double)duration
{
  NSMutableArray *logs = [NSMutableArray array];
  NSString *testCaseFullName = [NSString stringWithFormat:@"-[%@.%@ %@]", testBundleName, testClassName, testMethodName];
  [logs addObject:[NSString stringWithFormat:@"Test Case '%@' started.", testCaseFullName]];

  double testStartTimeInterval = 0;
  BOOL startTimeSet = NO;
  for (NSDictionary *activitySummary in activitySummaries) {
    if (!startTimeSet) {
      testStartTimeInterval = readDoubleFromDict(activitySummary, @"StartTimeInterval");
      startTimeSet = YES;
    }

    NSString *activityType = readStringFromDict(activitySummary, @"ActivityType");
    if ([activityType isEqualToString:@"com.apple.dt.xctest.activity-type.internal"]) {
      [self addTestLogsFromLegacyActivitySummary:activitySummary logs:logs testStartTimeInterval:testStartTimeInterval indent:0];
    }
  }

  [logs addObject:[NSString stringWithFormat:@"Test Case '%@' %@ in %.3f seconds", testCaseFullName, testPassed ? @"passed" : @"failed", duration]];
  return logs;
}

+ (void)addTestLogsFromLegacyActivitySummary:(NSDictionary *)activitySummary logs:(NSMutableArray<NSString *> *)logs testStartTimeInterval:(double)testStartTimeInterval indent:(NSUInteger)indent
{
  NSAssert([activitySummary isKindOfClass:NSDictionary.class], @"activitySummary not a NSDictionary");
  NSString *message = readStringFromDict(activitySummary, @"Title");
  double startTimeInterval = readDoubleFromDict(activitySummary, @"StartTimeInterval");
  double elapsed = startTimeInterval - testStartTimeInterval;
  NSString *indentString = [@"" stringByPaddingToLength:1 + indent * 4 withString:@" " startingAtIndex:0];
  NSString *log = [NSString stringWithFormat:@"    t = %8.2fs%@%@", elapsed, indentString, message];
  [logs addObject:log];

  NSArray<NSDictionary *> *subActivities = (NSArray<NSDictionary *> *) activitySummary[@"SubActivities"];
  if (!subActivities) {
    return;
  }
  NSAssert([subActivities isKindOfClass:NSArray.class], @"subActivities is not a NSArray");

  for (NSDictionary *subActivity in subActivities) {
    [self addTestLogsFromLegacyActivitySummary:subActivity logs:logs testStartTimeInterval:testStartTimeInterval indent:indent + 1];
  }
}

+ (NSString *)buildErrorMessageLegacy:(NSArray<NSDictionary *> *)failureSummmaries {
  NSMutableArray *messages = [NSMutableArray array];
  for (NSDictionary *failureSummary in failureSummmaries) {
    NSAssert([failureSummary isKindOfClass:NSDictionary.class], @"failureSummary is not a NSDictionary");
    [messages addObject:readStringFromDict(failureSummary, @"Message")];
  }

  return [messages componentsJoinedByString:@"\n"];
}

#pragma mark Private: Xcode 11+ XCTest Result Parsing

+ (NSArray<NSString *> *)parseActions:(NSDictionary<NSString *, NSObject *> *)actions logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(actions, @"Test actions is nil");
  NSAssert([actions isKindOfClass:NSDictionary.class], @"Test actions not a NSDictionary");

  NSArray<NSDictionary *> *actionValues = unwrapValues(actions);
  NSAssert(actionValues, @"action values is nil");

  NSMutableArray<NSString *> *ids = [[NSMutableArray alloc] init];
  for (NSDictionary<NSString *, NSDictionary *> *action in actionValues) {
    [ids addObject:[self parseAction:action logger:logger]];
  }
  return ids;
}

+ (NSString *)parseAction:(NSDictionary<NSString *, NSDictionary *> *)action logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(action, @"action is nil");
  NSAssert([action isKindOfClass:NSDictionary.class], @"action not a NSDictionary");

  NSDictionary<NSString *, NSDictionary *> *actionResult = action[@"actionResult"];
  return [self parseActionResult:actionResult logger:logger];
}

+ (NSString *)parseActionResult:(NSDictionary<NSString *, NSDictionary *> *)actionResult logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(actionResult, @"action result is nil");
  NSAssert([actionResult isKindOfClass:NSDictionary.class], @"action result not a NSDictionary");

  NSDictionary<NSString *, NSDictionary *> *testsRef = actionResult[@"testsRef"];
  return [self parseTestsRef:testsRef logger:logger];
}

+ (NSString *)parseTestsRef:(NSDictionary<NSString *, NSDictionary *> *)testsRef logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testsRef, @"tests ref is nil");
  NSAssert([testsRef isKindOfClass:NSDictionary.class], @"tests ref not a NSDictionary");

  return (NSString *)accessAndUnwrapValue(testsRef, @"id", logger);
}

+ (void)reportSummaries:(NSArray<NSDictionary *> *)summaries
               reporter:(id<FBTestManagerTestReporter>)reporter
                  queue:(dispatch_queue_t)queue
       resultBundlePath:(NSString *)resultBundlePath
                 logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(summaries, @"Test summaries have no value");
  NSAssert([summaries isKindOfClass:NSArray.class], @"Test summary values not a NSArray");

  for (NSDictionary<NSString *, NSDictionary *> *summary in summaries) {
    [self reportResults:summary reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportResults:(NSDictionary<NSString *, NSDictionary *> *)results
             reporter:(id<FBTestManagerTestReporter>)reporter
                queue:(dispatch_queue_t)queue
     resultBundlePath:(NSString *)resultBundlePath
               logger:(id<FBControlCoreLogger>)logger
{
  NSAssert([results isKindOfClass:NSDictionary.class], @"Test results not a NSDictionary");
  NSArray<NSDictionary *> *testTargets = accessAndUnwrapValues(results, @"testableSummaries", logger);

  [self reportTargetTests:testTargets reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
}

+ (void)reportTargetTests:(NSArray<NSDictionary *> *)targetTests
                 reporter:(id<FBTestManagerTestReporter>)reporter
                    queue:(dispatch_queue_t)queue
         resultBundlePath:(NSString *)resultBundlePath
                   logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(targetTests, @"targetTests is nil");
  NSAssert([targetTests isKindOfClass:NSArray.class], @"targetTests not a NSArray");

  for (NSDictionary<NSString *, NSDictionary *> *targetTest in targetTests) {
    [self reportTargetTest:targetTest reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportTargetTest:(NSDictionary<NSString *, NSDictionary *> *)targetTest
                reporter:(id<FBTestManagerTestReporter>)reporter
                   queue:(dispatch_queue_t)queue
        resultBundlePath:(NSString *)resultBundlePath
                  logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(targetTest, @"targetTest is nil");
  NSAssert([targetTest isKindOfClass:NSDictionary.class], @"targetTest not a NSDictionary");
  NSString *testBundleName = (NSString *)accessAndUnwrapValue(targetTest, @"targetName", logger);

  NSArray<NSDictionary *> *selectedTests = accessAndUnwrapValues(targetTest, @"tests", logger);
  if (selectedTests != nil) {
    [self reportSelectedTests:selectedTests testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
  else {
    [logger log:@"Test failed and no test results found in the bundle"];
    NSArray *failureSummaries = accessAndUnwrapValues(targetTest, @"failureSummaries", logger);
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:@"" method:@"" withMessage:[self buildErrorMessage:failureSummaries logger:logger] file:nil line:0];
  }
}

+ (void)reportSelectedTests:(NSArray<NSDictionary *> *)selectedTests
             testBundleName:(NSString *)testBundleName
                   reporter:(id<FBTestManagerTestReporter>)reporter
                      queue:(dispatch_queue_t)queue
           resultBundlePath:(NSString *)resultBundlePath
                     logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(selectedTests, @"selectedTests is nil");
  NSAssert([selectedTests isKindOfClass:NSArray.class], @"selectedTests not a NSArray");

  for (NSDictionary *selectedTest in selectedTests) {
    [self reportSelectedTest:selectedTest testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportSelectedTest:(NSDictionary<NSString *, NSDictionary *> *)selectedTest
            testBundleName:(NSString *)testBundleName
                  reporter:(id<FBTestManagerTestReporter>)reporter
                     queue:(dispatch_queue_t)queue
          resultBundlePath:(NSString *)resultBundlePath
                    logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(selectedTest, @"selectedTest is nil");
  NSAssert([selectedTest isKindOfClass:NSDictionary.class], @"selectedTest not a NSDictionary");

  NSArray<NSDictionary *> *testTargetXctests = accessAndUnwrapValues(selectedTest, @"subtests", logger);
  if (testTargetXctests != nil) {
    [self reportTestTargetXctests:testTargetXctests testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
  else {
    [logger log:@"Test failed and no target test results found in the bundle"];
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:@"" method:@"" withMessage:@"" file:nil line:0];
  }
}

+ (void)reportTestTargetXctests:(NSArray<NSDictionary *> *)testTargetXctests
                 testBundleName:(NSString *)testBundleName
                       reporter:(id<FBTestManagerTestReporter>)reporter
                          queue:(dispatch_queue_t)queue
               resultBundlePath:(NSString *)resultBundlePath
                         logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testTargetXctests, @"testTargetXctests is nil");
  NSAssert([testTargetXctests isKindOfClass:NSArray.class], @"testTargetXctests not a NSArray");

  for (NSDictionary *testTargetXctest in testTargetXctests) {
    [self reportTestTargetXctest:testTargetXctest testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportTestTargetXctest:(NSDictionary<NSString *, NSDictionary *> *)testTargetXctest
                testBundleName:(NSString *)testBundleName
                      reporter:(id<FBTestManagerTestReporter>)reporter
                         queue:(dispatch_queue_t)queue
              resultBundlePath:(NSString *)resultBundlePath
                        logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testTargetXctest, @"selectedTest is nil");
  NSAssert([testTargetXctest isKindOfClass:NSDictionary.class], @"testTargetXctest not a NSDictionary");

  NSArray *testClasses = accessAndUnwrapValues(testTargetXctest, @"subtests", logger);
  if (testClasses != nil) {
    [self reportTestClasses:testClasses testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
  else {
    [logger log:@"Test failed and no test class results found in the bundle"];
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:@"" method:@"" withMessage:@"" file:nil line:0];
  }
}

+ (void)reportTestClasses:(NSArray<NSDictionary *> *)testClasses
           testBundleName:(NSString *)testBundleName
                 reporter:(id<FBTestManagerTestReporter>)reporter
                    queue:(dispatch_queue_t)queue
         resultBundlePath:(NSString *)resultBundlePath
                   logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testClasses, @"selectedTest is nil");
  NSAssert([testClasses isKindOfClass:NSArray.class], @"testClasses not a NSArray");

  for (NSDictionary *testClass in testClasses) {
    [self reportTestClass:testClass testBundleName:testBundleName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportTestClass:(NSDictionary<NSString *, NSDictionary *> *)testClass
         testBundleName:(NSString *)testBundleName
               reporter:(id<FBTestManagerTestReporter>)reporter
                  queue:(dispatch_queue_t)queue
       resultBundlePath:(NSString *)resultBundlePath
                 logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testClass, @"selectedTest is nil");
  NSAssert([testClass isKindOfClass:NSDictionary.class], @"testClass not a NSDictionary");

  NSString *testClassName = (NSString *)accessAndUnwrapValue(testClass, @"identifier", logger);
  NSArray<NSDictionary *> *testMethods = accessAndUnwrapValues(testClass, @"subtests", logger);
  if (testMethods != nil) {
    [self reportTestMethods:testMethods testBundleName:testBundleName testClassName:testClassName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
  else {
    [logger logFormat:@"Test failed for %@ and no test method results found", testClassName];
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:testClassName method:@"" withMessage:@"" file:nil line:0];
  }
}

+ (void)reportTestMethods:(NSArray<NSDictionary *> *)testMethods
           testBundleName:(NSString *)testBundleName
            testClassName:(NSString *)testClassName
                 reporter:(id<FBTestManagerTestReporter>)reporter
                    queue:(dispatch_queue_t)queue
         resultBundlePath:(NSString *)resultBundlePath
                   logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testMethods, @"testMethods is nil");
  NSAssert([testMethods isKindOfClass:NSArray.class], @"testMethods not a NSArray");

  for (NSDictionary *testMethod in testMethods) {
    [self reportTestMethod:testMethod testBundleName:testBundleName testClassName:testClassName reporter:reporter queue:queue resultBundlePath:resultBundlePath logger:logger];
  }
}

+ (void)reportTestMethod:(NSDictionary<NSString *, NSDictionary *> *)testMethod
          testBundleName:(NSString *)testBundleName
           testClassName:(NSString *)testClassName
                reporter:(id<FBTestManagerTestReporter>)reporter
                   queue:(dispatch_queue_t)queue
        resultBundlePath:(NSString *)resultBundlePath
                  logger:(id<FBControlCoreLogger>)logger
{
  NSAssert(testMethod, @"testMethod is nil");
  NSAssert([testMethod isKindOfClass:NSDictionary.class], @"testMethod not a NSDictionary");

  NSString *testStatus = (NSString *)accessAndUnwrapValue(testMethod, @"testStatus", logger);
  NSString *testMethodIdentifier = (NSString *)accessAndUnwrapValue(testMethod, @"identifier", logger);
  NSNumber *duration = (NSNumber *)accessAndUnwrapValue(testMethod, @"duration", logger);

  FBTestReportStatus status = FBTestReportStatusUnknown;
  if ([testStatus isEqualToString:@"Success"]) {
    status = FBTestReportStatusPassed;
  }
  if ([testStatus isEqualToString:@"Failure"]) {
    status = FBTestReportStatusFailed;
  }

  [reporter testManagerMediator:nil testCaseDidStartForTestClass:testClassName method:testMethodIdentifier];

  NSDictionary<NSString *, NSDictionary *> *summaryRef = testMethod[@"summaryRef"];
  NSAssert(summaryRef, @"Summary reference is nil");
  NSAssert([summaryRef isKindOfClass:NSDictionary.class], @"Summary reference not a NSDictionary");
  NSString *summaryRefId = (NSString *)accessAndUnwrapValue(summaryRef, @"id", logger);
  if (summaryRefId != nil) {
    [[[FBXCTestResultToolOperation
      getJSONFrom:resultBundlePath forId:summaryRefId queue:queue logger:logger]
      onQueue:queue doOnResolved:^(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *actionTestSummary) {
        if (status == FBTestReportStatusFailed) {
          NSArray *failureSummaries = accessAndUnwrapValues(actionTestSummary, @"failureSummaries", logger);
          [reporter testManagerMediator:nil testCaseDidFailForTestClass:testClassName method:testMethodIdentifier withMessage:[self buildErrorMessage:failureSummaries logger:logger] file:nil line:0];
        }

        NSArray<NSDictionary *> *performanceMetrics = accessAndUnwrapValues(actionTestSummary, @"performanceMetrics", logger);
        if (performanceMetrics != nil) {
          NSString *testMethodName = (NSString *)accessAndUnwrapValue(testMethod, @"name", logger);
          NSString *suffix = @"()";
          if ([testMethodName hasSuffix:suffix]) {
            testMethodName = [testMethodName substringToIndex:[testMethodName length] - [suffix length]];
          }
          [self savePerformanceMetrics:performanceMetrics toTestResultBundle:resultBundlePath forTestTarget:testBundleName testClass:testClassName testMethod:testMethodName logger:logger];
        }

        NSArray<NSDictionary *> *activitySummaries = accessAndUnwrapValues(actionTestSummary, @"activitySummaries", logger);
        [self extractScreenshotsFromActivities:activitySummaries queue:queue resultBundlePath:resultBundlePath logger:logger];

        if ([reporter respondsToSelector:@selector(testManagerMediator:testCaseDidFinishForTestClass:method:withStatus:duration:logs:)]) {
          NSMutableArray *logs = [self buildTestLog:activitySummaries
                                     testBundleName:testBundleName
                                      testClassName:testClassName
                                     testMethodName:testMethodIdentifier
                                         testPassed:status == FBTestReportStatusPassed
                                           duration:[duration doubleValue]
                                             logger:logger];
          [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodIdentifier withStatus:status duration:[duration doubleValue] logs:[logs copy]];
        }
        else {
          [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodIdentifier withStatus:status duration:[duration doubleValue]];
        }
    }] awaitWithTimeout:XCTestOperationTimeoutSecs error:nil];
  }
}

+ (NSMutableArray<NSString *> *)buildTestLog:(NSArray<NSDictionary *> *)activitySummaries
                              testBundleName:(NSString *)testBundleName
                               testClassName:(NSString *)testClassName
                              testMethodName:(NSString *)testMethodName
                                  testPassed:(BOOL)testPassed
                                    duration:(double)duration
                                      logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray *logs = [NSMutableArray array];
  NSString *testCaseFullName = [NSString stringWithFormat:@"-[%@.%@ %@]", testBundleName, testClassName, testMethodName];
  [logs addObject:[NSString stringWithFormat:@"Test Case '%@' started.", testCaseFullName]];

  double testStartTimeInterval = 0;
  BOOL startTimeSet = NO;
  for (NSDictionary *activitySummary in activitySummaries) {
    if (!startTimeSet) {
      NSDate *date = dateFromString((NSString *)accessAndUnwrapValue(activitySummary, @"start", logger));
      testStartTimeInterval = [date timeIntervalSince1970];
      startTimeSet = YES;
    }

    NSString *activityType = (NSString *)accessAndUnwrapValue(activitySummary, @"activityType", logger);
    if ([activityType isEqualToString:@"com.apple.dt.xctest.activity-type.internal"]) {
      [self addTestLogsFromActivitySummary:activitySummary logs:logs testStartTimeInterval:testStartTimeInterval indent:0 logger:logger];
    }
  }

  [logs addObject:[NSString stringWithFormat:@"Test Case '%@' %@ in %.3f seconds", testCaseFullName, testPassed ? @"passed" : @"failed", duration]];
  return logs;
}

+ (void)addTestLogsFromActivitySummary:(NSDictionary *)activitySummary logs:(NSMutableArray<NSString *> *)logs testStartTimeInterval:(double)testStartTimeInterval indent:(NSUInteger)indent logger:(id<FBControlCoreLogger>)logger
{
  NSAssert([activitySummary isKindOfClass:NSDictionary.class], @"activitySummary not a NSDictionary");
  NSString *message = (NSString *)accessAndUnwrapValue(activitySummary, @"title", logger);
  NSDate *date = dateFromString((NSString *)accessAndUnwrapValue(activitySummary, @"start", logger));
  double startTimeInterval = [date timeIntervalSince1970];
  double elapsed = startTimeInterval - testStartTimeInterval;
  NSString *indentString = [@"" stringByPaddingToLength:1 + indent * 4 withString:@" " startingAtIndex:0];
  NSString *log = [NSString stringWithFormat:@"    t = %8.2fs%@%@", elapsed, indentString, message];
  [logs addObject:log];

  NSDictionary<NSString *, NSObject *> *wrappedSubActivities = activitySummary[@"subactivities"];
  if (!wrappedSubActivities) {
    return;
  }
  NSArray<NSDictionary *> *subActivities = unwrapValues(wrappedSubActivities);
  NSAssert([subActivities isKindOfClass:NSArray.class], @"subActivities is not a NSArray");

  for (NSDictionary *subActivity in subActivities) {
    [self addTestLogsFromActivitySummary:subActivity logs:logs testStartTimeInterval:testStartTimeInterval indent:indent + 1 logger:logger];
  }
}

+ (void)extractScreenshotsFromActivities:(NSArray<NSDictionary *> *)activities
                                         queue:(dispatch_queue_t)queue
                              resultBundlePath:(NSString *)resultBundlePath
                                        logger:(id<FBControlCoreLogger>)logger
{
  // Extract all screenshots to the "Attachments" folder just as in the legacy test result bundle
  NSString *screenshotsPath = [self ensureSubdirectory:@"Attachments" insideResultBundle:resultBundlePath];
  for (NSDictionary *activity in activities) {
    if (activity[@"attachments"]) {
      NSArray<NSDictionary *> *attachments = accessAndUnwrapValues(activity, @"attachments", logger);
      [self extractScreenshotsFromAttachments:attachments to:screenshotsPath queue:queue resultBundlePath:resultBundlePath logger:logger];
    }
    if (activity[@"subactivities"]) {
      NSArray<NSDictionary *> *subactivities = accessAndUnwrapValues(activity, @"subactivities", logger);
      [self extractScreenshotsFromActivities:subactivities queue:queue resultBundlePath:resultBundlePath logger:logger];
    }
  }
}

+ (NSString *)ensureSubdirectory:(NSString *)subdirectory insideResultBundle:(NSString *)resultBundlePath {
  NSError *error = nil;
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSString *subdirectoryFullPath = [resultBundlePath stringByAppendingPathComponent:subdirectory];
  BOOL isDirectory = NO;
  if ([fileManager fileExistsAtPath:subdirectoryFullPath isDirectory:&isDirectory]) {
    if (!isDirectory) {
      return [[FBControlCoreError describeFormat:@"%@ is not a directory", subdirectoryFullPath] fail:&error];
    }
  } else {
    if (![fileManager createDirectoryAtPath:subdirectoryFullPath withIntermediateDirectories:NO attributes:nil error:&error]) {
      return [[FBControlCoreError describeFormat:@"Failed to create directory at %@", subdirectoryFullPath] fail:&error];
    }
  }
  return subdirectoryFullPath;
}

+ (void)extractScreenshotsFromAttachments:(NSArray<NSDictionary *> *)attachments
                                       to:(NSString *)destination
                                    queue:(dispatch_queue_t)queue
                         resultBundlePath:(NSString *)resultBundlePath
                                   logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^Screenshot_.*\\.jpg$" options:0 error:&error];
  NSAssert(regex, @"Screenshot filename regex failed to compile %@", error);
  for (NSDictionary<NSString *, NSDictionary *> *attachment in attachments) {
    if (attachment[@"filename"]) {
      NSString *filename = (NSString *)accessAndUnwrapValue(attachment, @"filename", logger);
      NSTextCheckingResult *matchResult = [regex firstMatchInString:filename options:0 range:NSMakeRange(0, [filename length])];
      if (attachment[@"payloadRef"] && matchResult) {
        NSString *timestamp = (NSString *)accessAndUnwrapValue(attachment, @"timestamp", logger);
        NSString *exportPath = [destination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@", timestamp, filename]];
        NSDictionary<NSString *, NSDictionary *> *payloadRef = attachment[@"payloadRef"];
        NSAssert(payloadRef, @"Screenshot payload reference is empty");
        NSString *screenshotId = (NSString *)accessAndUnwrapValue(payloadRef, @"id", logger);
        [[FBXCTestResultToolOperation exportFileFrom:resultBundlePath to:exportPath forId:screenshotId queue:queue logger:logger] awaitWithTimeout:XCTestOperationTimeoutSecs error:nil];
      }
    }
  }
}

+ (void)savePerformanceMetrics:(NSArray<NSDictionary *> *)performanceMetrics
            toTestResultBundle:(NSString *)resultBundlePath
                 forTestTarget:(NSString *)testTarget
                     testClass:(NSString *)testClass
                    testMethod:(NSString *)testMethod
                        logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray *metrics = [NSMutableArray new];
  for (NSDictionary<NSString *, NSDictionary *> *performanceMetric in performanceMetrics) {
    NSString *metricName = accessAndUnwrapValue(performanceMetric, @"displayName", logger);
    NSString *metricUnit = accessAndUnwrapValue(performanceMetric, @"unitOfMeasurement", logger);
    NSString *metricIdentifier = accessAndUnwrapValue(performanceMetric, @"identifier", logger);
    NSArray *metricMeasurements = accessAndUnwrapValues(performanceMetric, @"measurements", logger);
    NSMutableArray<NSNumber *> *measurements = [NSMutableArray new];
    for (NSDictionary *metricMeasurement in metricMeasurements) {
      [measurements addObject:(NSNumber *)unwrapValue(metricMeasurement)];
    }
    NSDictionary *metric = [[NSDictionary alloc] initWithObjectsAndKeys:
                            metricName, @"name",
                            metricUnit, @"unit",
                            metricIdentifier, @"identifier",
                            measurements, @"measurements",
                            nil];
    [metrics addObject:metric];
  }

  if ([NSJSONSerialization isValidJSONObject:metrics]) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:metrics options:NSJSONWritingPrettyPrinted error:&error];
    if (error != nil) {
      [logger logFormat:@"Failed to serilize performance metrics %@ with error %@", metrics, error];
    }
    else if (json != nil) {
      NSString *performanceMetricsDirectory = [self ensureSubdirectory:@"Metrics" insideResultBundle:resultBundlePath];
      NSString *metricFilePath = [performanceMetricsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@_%@.json", testTarget, testClass, testMethod]];
      [json writeToFile:metricFilePath atomically:YES];
    }
  }
}

+ (NSString *)buildErrorMessage:(NSArray<NSDictionary *> *)failureSummmaries logger:(id<FBControlCoreLogger>)logger {
  NSMutableArray *messages = [NSMutableArray array];
  for (NSDictionary *failureSummary in failureSummmaries) {
    NSAssert([failureSummary isKindOfClass:NSDictionary.class], @"failureSummary is not a NSDictionary");
    [messages addObject:(NSString *)accessAndUnwrapValue(failureSummary, @"message", logger)];
  }

  return [messages componentsJoinedByString:@"\n"];
}

@end

NS_ASSUME_NONNULL_END
