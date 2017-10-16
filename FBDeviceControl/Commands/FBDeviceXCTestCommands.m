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

+ (void)reportTestMethod:(NSDictionary<NSString *, NSObject *> *)testMethod testClassName:(NSString *)testClassName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testMethod, @"testMethod is nil");
  NSAssert([testMethod isKindOfClass:NSDictionary.class], @"testMethod not a NSDictionary");

  NSString *testStatus = (NSString *)testMethod[@"TestStatus"];
  NSAssert(testStatus, @"testStatus is nil");
  NSAssert([testStatus isKindOfClass:NSString.class], @"testStatus not a NSString");

  NSString *testMethodName = (NSString *)testMethod[@"TestIdentifier"];
  NSAssert(testMethodName, @"testMethodName is nil");
  NSAssert([testMethodName isKindOfClass:NSString.class], @"testMethodName not a NSString");

  NSNumber *duration = (NSNumber *)testMethod[@"Duration"];
  NSAssert(duration, @"duration is nil");
  NSAssert([duration isKindOfClass:NSNumber.class], @"duration not a NSNumber");

  FBTestReportStatus status = FBTestReportStatusUnknown;
  if ([testStatus isEqualToString:@"Success"]) {
    status = FBTestReportStatusPassed;
  }
  if ([testStatus isEqualToString:@"Failure"]) {
    status = FBTestReportStatusFailed;
  }
  [reporter testManagerMediator:nil testCaseDidStartForTestClass:testClassName method:testMethodName];
  [reporter testManagerMediator:nil testCaseDidFinishForTestClass:testClassName method:testMethodName withStatus:status duration:[duration doubleValue]];
}

+ (void)reportTestMethods:(NSArray<NSDictionary *> *)testMethods testClassName:(NSString *)testClassName reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testMethods, @"testMethods is nil");
  NSAssert([testMethods isKindOfClass:NSArray.class], @"testMethods not a NSArray");

  for (NSDictionary *testMethod in testMethods) {
    [self reportTestMethod:testMethod testClassName:testClassName reporter:reporter];
  }
}

+ (void)reportTestClass:(NSDictionary<NSString *, NSObject *> *)testClass reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testClass, @"selectedTest is nil");
  NSAssert([testClass isKindOfClass:NSDictionary.class], @"testClass not a NSDictionary");

  NSString *testClassName = (NSString *)testClass[@"TestIdentifier"];
  NSAssert(testClassName, @"testClassName is nil");
  NSAssert([testClassName isKindOfClass:NSString.class], @"testClassName not a NSString");

  NSArray<NSDictionary *> *testMethods = (NSArray<NSDictionary *> *)testClass[@"Subtests"];
  [self reportTestMethods:testMethods testClassName:testClassName reporter:reporter];
}

+ (void)reportTestClasses:(NSArray<NSDictionary *> *)testClasses reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testClasses, @"selectedTest is nil");
  NSAssert([testClasses isKindOfClass:NSArray.class], @"testClasses not a NSArray");

  for (NSDictionary *testClass in testClasses) {
    [self reportTestClass:testClass reporter:reporter];
  }
}

+ (void)reportTestTargetXctest:(NSDictionary<NSString *, NSObject *> *)testTargetXctest reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctest, @"selectedTest is nil");
  NSAssert([testTargetXctest isKindOfClass:NSDictionary.class], @"testTargetXctest not a NSDictionary");

  NSArray *testClasses = (NSArray *)testTargetXctest[@"Subtests"];
  [self reportTestClasses:testClasses reporter:reporter];
}

+ (void)reportTestTargetXctests:(NSArray<NSDictionary *> *)testTargetXctests reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(testTargetXctests, @"testTargetXctests is nil");
  NSAssert([testTargetXctests isKindOfClass:NSArray.class], @"testTargetXctests not a NSArray");

  for (NSDictionary *testTargetXctest in testTargetXctests) {
    [self reportTestTargetXctest:testTargetXctest reporter:reporter];
  }
}

+ (void)reportSelectedTest:(NSDictionary<NSString *, NSObject *> *)selectedTest reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTest, @"selectedTest is nil");
  NSAssert([selectedTest isKindOfClass:NSDictionary.class], @"selectedTest not a NSDictionary");

  NSArray<NSDictionary *> *testTargetXctests = (NSArray<NSDictionary *> *)selectedTest[@"Subtests"];
  [self reportTestTargetXctests:testTargetXctests reporter:reporter];
}

+ (void)reportSelectedTests:(NSArray<NSDictionary *> *)selectedTests reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(selectedTests, @"selectedTests is nil");
  NSAssert([selectedTests isKindOfClass:NSArray.class], @"selectedTests not a NSArray");

  for (NSDictionary *selectedTest in selectedTests) {
    [self reportSelectedTest:selectedTest reporter:reporter];
  }
}

+ (void)reportTargetTest:(NSDictionary<NSString *, NSObject *> *)targetTest reporter:(id<FBTestManagerTestReporter>)reporter
{
  NSAssert(targetTest, @"targetTest is nil");
  NSAssert([targetTest isKindOfClass:NSDictionary.class], @"targetTest not a NSDictionary");

  NSArray<NSDictionary *> *selectedTests = (NSArray<NSDictionary *> *)targetTest[@"Tests"];
  [self reportSelectedTests:selectedTests reporter:reporter];
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

- (nullable id<FBXCTestOperation>)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter error:(NSError **)error
{
  // Return early and fail if there is already a test run for the device.
  // There should only ever be one test run per-device.
  if (self.operation) {
    return [[FBDeviceControlError
             describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
            fail:error];
  }
  // Terminate the reparented xcodebuild invocations.
  NSError *innerError = nil;
  if (![FBXcodeBuildOperation terminateReparentedXcodeBuildProcessesForTarget:self.device processFetcher:self.processFetcher error:&innerError]) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Create the .xctestrun file
  NSString *filePath = [self createXCTestRunFileFromConfiguration:testLaunchConfiguration error:&innerError];
  if (!filePath) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Find the path to xcodebuild
  NSString *xcodeBuildPath = [FBDeviceXCTestCommands xcodeBuildPathWithError:&innerError];
  if (!xcodeBuildPath) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Create the Task, wrap it and store it
  _operation = [FBXcodeBuildOperation operationWithTarget:self.device configuration:testLaunchConfiguration xcodeBuildPath:xcodeBuildPath testRunFilePath:filePath];

  if (reporter != nil) {
    [self.operation.completed onQueue:self.device.workQueue notifyOfCompletion:^(FBFuture *task) {
      if (testLaunchConfiguration.resultBundlePath) {
        NSString *testSummariesPath = [testLaunchConfiguration.resultBundlePath stringByAppendingPathComponent:@"TestSummaries.plist"];
        NSDictionary<NSString *, NSArray *> *results = [NSDictionary dictionaryWithContentsOfFile:testSummariesPath];
        [self.class reportResults:results reporter:reporter];
      }
      [reporter testManagerMediatorDidFinishExecutingTestPlan:nil];
      self->_operation = nil;
    }];
  }

  return _operation;
}

- (NSArray<id<FBXCTestOperation>> *)testOperations
{
  id<FBXCTestOperation> operation = self.operation;
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

@end
