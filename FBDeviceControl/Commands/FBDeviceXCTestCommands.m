/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBDevice.h"
#import "FBDeviceXCTestCommands.h"
#import "FBDeviceControlError.h"

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

@interface FBDeviceXCTestCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readonly) FBXcodeBuildOperation *operation;

@end

@implementation FBDeviceXCTestCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target workingDirectory:NSTemporaryDirectory()];
}

- (instancetype)initWithDevice:(FBDevice *)device workingDirectory:(NSString *)workingDirectory
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _workingDirectory = workingDirectory;
  _processFetcher = [FBProcessFetcher new];

  return self;
}

#pragma mark Public

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
  NSMutableArray *logs = [self buildTestLog:activitySummaries
                             testBundleName:testBundleName
                              testClassName:testClassName
                             testMethodName:testMethodName
                                 testPassed:status == FBTestReportStatusPassed
                                   duration:[duration doubleValue]];

  [reporter testManagerMediator:nil testCaseDidStartForTestClass:testClassName method:testMethodName];
  if (status == FBTestReportStatusFailed) {
    NSArray *failureSummaries = readArrayFromDict(testMethod, @"FailureSummaries");
    [reporter testManagerMediator:nil testCaseDidFailForTestClass:testClassName method:testMethodName withMessage:[self buildErrorMessage:failureSummaries] file:nil line:0];
  }

  if ([reporter respondsToSelector:@selector(testManagerMediator:testCaseDidFinishForTestClass:method:withStatus:duration:logs:)]) {
    [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodName withStatus:status duration:[duration doubleValue] logs:[logs copy]];
  }
  else {
    [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodName withStatus:status duration:[duration doubleValue]];
  }
}

+ (void)reportTestMethods:(NSArray<NSDictionary *> *)testMethods testBundleName:(NSString *)testBundleName testClassName:(NSString *)testClassName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testMethods, @"testMethods is nil");
  NSAssert([testMethods isKindOfClass:NSArray.class], @"testMethods not a NSArray");

  for (NSDictionary *testMethod in testMethods) {
    [self reportTestMethod:testMethod testBundleName:testBundleName testClassName:testClassName reporter:reporter];
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

+ (void)reportTestClasses:(NSArray<NSDictionary *> *)testClasses testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testClasses, @"selectedTest is nil");
  NSAssert([testClasses isKindOfClass:NSArray.class], @"testClasses not a NSArray");

  for (NSDictionary *testClass in testClasses) {
    [self reportTestClass:testClass testBundleName:testBundleName reporter:reporter];
  }
}

+ (void)reportTestTargetXctest:(NSDictionary<NSString *, NSObject *> *)testTargetXctest testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctest, @"selectedTest is nil");
  NSAssert([testTargetXctest isKindOfClass:NSDictionary.class], @"testTargetXctest not a NSDictionary");

  NSArray *testClasses = (NSArray *)testTargetXctest[@"Subtests"];
  [self reportTestClasses:testClasses testBundleName:testBundleName reporter:reporter];
}

+ (void)reportTestTargetXctests:(NSArray<NSDictionary *> *)testTargetXctests testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctests, @"testTargetXctests is nil");
  NSAssert([testTargetXctests isKindOfClass:NSArray.class], @"testTargetXctests not a NSArray");

  for (NSDictionary *testTargetXctest in testTargetXctests) {
    [self reportTestTargetXctest:testTargetXctest testBundleName:testBundleName reporter:reporter];
  }
}

+ (void)reportSelectedTest:(NSDictionary<NSString *, NSObject *> *)selectedTest testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTest, @"selectedTest is nil");
  NSAssert([selectedTest isKindOfClass:NSDictionary.class], @"selectedTest not a NSDictionary");

  NSArray<NSDictionary *> *testTargetXctests = (NSArray<NSDictionary *> *)selectedTest[@"Subtests"];
  [self reportTestTargetXctests:testTargetXctests testBundleName:testBundleName reporter:reporter];
}

+ (void)reportSelectedTests:(NSArray<NSDictionary *> *)selectedTests testBundleName:(NSString *)testBundleName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTests, @"selectedTests is nil");
  NSAssert([selectedTests isKindOfClass:NSArray.class], @"selectedTests not a NSArray");

  for (NSDictionary *selectedTest in selectedTests) {
    [self reportSelectedTest:selectedTest testBundleName:testBundleName reporter:reporter];
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

+ (void)reportTargetTests:(NSArray<NSDictionary *> *)targetTests reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(targetTests, @"targetTests is nil");
  NSAssert([targetTests isKindOfClass:NSArray.class], @"targetTests not a NSArray");

  for (NSDictionary<NSString *, NSObject *> *targetTest in targetTests) {
    [self reportTargetTest:targetTest reporter:reporter];
  }
}

+ (void)reportResults:(NSDictionary<NSString *, NSArray *> *)results reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(results, @"results is nil");
  NSAssert([results isKindOfClass:NSDictionary.class], @"Test results not a NSDictionary");
  NSArray<NSDictionary *> *testTargets = results[@"TestableSummaries"];

  [self reportTargetTests:testTargets reporter:reporter];
}

#pragma mark FBXCTestCommands Implementation

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nonnull id<FBControlCoreLogger>)logger
{
  // Return early and fail if there is already a test run for the device.
  // There should only ever be one test run per-device.
  if (self.operation) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
      failFuture];
  }
  // Terminate the reparented xcodebuild invocations.
  NSError *error = nil;
  if (![FBXcodeBuildOperation terminateReparentedXcodeBuildProcessesForTarget:self.device processFetcher:self.processFetcher error:&error]) {
    return [FBDeviceControlError failFutureWithError:error];
  }

  // Create the .xctestrun file
  NSString *filePath = [self createXCTestRunFileFromConfiguration:testLaunchConfiguration error:&error];
  if (!filePath) {
    return [FBDeviceControlError failFutureWithError:error];
  }

  // Find the path to xcodebuild
  NSString *xcodeBuildPath = [FBDeviceXCTestCommands xcodeBuildPathWithError:&error];
  if (!xcodeBuildPath) {
    return [FBDeviceControlError failFutureWithError:error];
  }

  // Create the Task, wrap it and store it
  _operation = [FBXcodeBuildOperation operationWithTarget:self.device configuration:testLaunchConfiguration xcodeBuildPath:xcodeBuildPath testRunFilePath:filePath];

  if (reporter != nil) {
    [self.operation.completed onQueue:self.device.workQueue notifyOfCompletion:^(FBFuture *task) {
      if (testLaunchConfiguration.resultBundlePath) {
        NSString *testSummariesPath = [testLaunchConfiguration.resultBundlePath stringByAppendingPathComponent:@"TestSummaries.plist"];
        NSDictionary<NSString *, NSArray *> *results = [NSDictionary dictionaryWithContentsOfFile:testSummariesPath];
        [self.class reportResults:results reporter:reporter];
        [logger logFormat:@"ResultBundlePath: %@", testLaunchConfiguration.resultBundlePath];
      }
      [reporter testManagerMediatorDidFinishExecutingTestPlan:nil];
      self->_operation = nil;
    }];
  }

  return [FBFuture futureWithResult:_operation];
}

- (NSArray<id<FBiOSTargetContinuation>> *)testOperations
{
  id<FBiOSTargetContinuation> operation = self.operation;
  return operation ? @[operation] : @[];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  return [[FBDeviceControlError
    describeFormat:@"Cannot list the tests in bundle %@ as this is not supported on devices", bundlePath]
    failFuture];
}

#pragma mark Private


+ (NSDictionary<NSString *, id> *)overwriteXCTestRunPropertiesWithBaseProperties:(NSDictionary<NSString *, id> *)baseProperties newProperties:(NSDictionary<NSString *, id> *)newProperties
{
  NSMutableDictionary<NSString *, id> *mutableTestRunProperties = [baseProperties mutableCopy];
  for (NSString *testId in mutableTestRunProperties) {
    NSMutableDictionary<NSString *, id> *mutableTestProperties = [[mutableTestRunProperties objectForKey:testId] mutableCopy];
    NSDictionary<NSString *, id> *defaultTestProperties = [newProperties objectForKey:@"StubBundleId"];
    for (id key in defaultTestProperties) {
      if ([mutableTestProperties objectForKey:key]) {
        mutableTestProperties[key] =  [defaultTestProperties objectForKey:key];
      }
    }
    mutableTestRunProperties[testId] = mutableTestProperties;
  }
  return [mutableTestRunProperties copy];
}

- (nullable NSString *)createXCTestRunFileFromConfiguration:(FBTestLaunchConfiguration *)configuration error:(NSError **)error
{
  NSString *fileName = [NSProcessInfo.processInfo.globallyUniqueString stringByAppendingPathExtension:@"xctestrun"];
  NSString *path = [self.workingDirectory stringByAppendingPathComponent:fileName];

  NSDictionary<NSString *, id> *defaultTestRunProperties = [FBXcodeBuildOperation xctestRunProperties:configuration];

  NSDictionary<NSString *, id> *testRunProperties = configuration.xcTestRunProperties
    ? [FBDeviceXCTestCommands overwriteXCTestRunPropertiesWithBaseProperties:configuration.xcTestRunProperties newProperties:defaultTestRunProperties]
    : defaultTestRunProperties;

  if (![testRunProperties writeToFile:path atomically:false]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to write to file %@", path]
      fail:error];
  }
  return path;
}

+ (NSString *)xcodeBuildPathWithError:(NSError **)error
{
  NSString *path = [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"/usr/bin/xcodebuild"];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return [[FBDeviceControlError
      describeFormat:@"xcodebuild does not exist at expected path %@", path]
      fail:error];
  }
  return path;
}

// This replicates the stdout from xcodebuild, but without all the garbage that xcodebuild outputs
+ (void)addTestLogsFromActivitySummary:(NSDictionary *)activitySummary logs:(NSMutableArray<NSString *> *)logs testStartTimeInterval:(double)testStartTimeInterval indent:(int)indent
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
    [self addTestLogsFromActivitySummary:subActivity logs:logs testStartTimeInterval:testStartTimeInterval indent:indent + 1];
  }
}

+ (NSMutableArray<NSString *> *)buildTestLog:(NSArray<NSDictionary *> *)activitySummaries
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
      [self addTestLogsFromActivitySummary:activitySummary logs:logs testStartTimeInterval:testStartTimeInterval indent:0];
    }
  }

  [logs addObject:[NSString stringWithFormat:@"Test Case '%@' %@ in %.3f seconds", testCaseFullName, testPassed ? @"passed" : @"failed", duration]];
  return logs;
}

+ (NSString *)buildErrorMessage:(NSArray<NSDictionary *> *)failureSummmaries {
  NSMutableArray *messages = [NSMutableArray array];
  for (NSDictionary *failureSummary in failureSummmaries) {
    NSAssert([failureSummary isKindOfClass:NSDictionary.class], @"failureSummary is not a NSDictionary");
    [messages addObject:readStringFromDict(failureSummary, @"Message")];
  }

  return [messages componentsJoinedByString:@"\n"];
}

@end
