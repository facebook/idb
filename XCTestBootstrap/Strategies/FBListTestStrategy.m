/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBListTestStrategy.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "ReporterEvents.h"

@interface FBListTestStrategy ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;
@property (nonatomic, strong, readonly) FBListTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBListTestStrategy_ReporterWrapped : NSObject <FBXCTestRunner>

@property (nonatomic, strong, readonly) FBListTestStrategy *strategy;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

@end

@implementation FBListTestStrategy_ReporterWrapped

- (instancetype)initWithStrategy:(FBListTestStrategy *)strategy reporter:(id<FBXCTestReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _strategy = strategy;
  _reporter = reporter;

  return self;
}


- (FBFuture<NSNull *> *)execute
{
  [self.reporter didBeginExecutingTestPlan];

  return [[self.strategy
    listTests]
    onQueue:self.strategy.executor.workQueue map:^(NSArray<NSString *> *testNames) {
      for (NSString *testName in testNames) {
        NSRange slashRange = [testName rangeOfString:@"/"];
        NSString *className = [testName substringToIndex:slashRange.location];
        NSString *methodName = [testName substringFromIndex:slashRange.location + 1];
        [self.reporter testCaseDidStartForTestClass:className method:methodName];
        [self.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0 logs:nil];
      }
      [self.reporter didFinishExecutingTestPlan];

      return NSNull.null;
    }];
}

@end

@implementation FBListTestStrategy

+ (instancetype)strategyWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithExecutor:executor configuration:configuration logger:logger];
}

- (instancetype)initWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _executor = executor;
  _configuration = configuration;
  _logger = logger;

  return self;
}

- (FBFuture<NSArray<NSString *> *> *)listTests
{
  id<FBConsumableBuffer> shimBuffer = FBDataBuffer.consumableBuffer;
  return [[[FBProcessOutput
    outputForDataConsumer:shimBuffer]
    providedThroughFile]
    onQueue:self.executor.workQueue fmap:^(id<FBProcessFileOutput> shimOutput) {
      return [self listTestsWithShimOutput:shimOutput shimBuffer:shimBuffer];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<NSString *> *> *)listTestsWithShimOutput:(id<FBProcessFileOutput>)shimOutput shimBuffer:(id<FBConsumableBuffer>)shimBuffer
{
  NSDictionary<NSString *, NSString *> *environment = @{
    @"DYLD_INSERT_LIBRARIES": self.executor.shimPath,
    @"TEST_SHIM_OUTPUT_PATH": shimOutput.filePath,
    @"TEST_SHIM_BUNDLE_PATH": self.configuration.testBundlePath,
  };
  id<FBConsumableBuffer> stdOutBuffer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer> stdOutConsumer = [FBCompositeDataConsumer consumerWithConsumers:@[
    stdOutBuffer,
    [FBLoggingDataConsumer consumerWithLogger:self.logger],
  ]];
  id<FBConsumableBuffer> stdErrBuffer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer> stdErrConsumer = [FBCompositeDataConsumer consumerWithConsumers:@[
    stdErrBuffer,
    [FBLoggingDataConsumer consumerWithLogger:self.logger],
  ]];

  return [[FBListTestStrategy
    listTestProcessWithConfiguration:self.configuration
    environment:environment
    stdOutConsumer:stdOutConsumer
    stdErrConsumer:stdErrConsumer
    executor:self.executor
    logger:self.logger]
    onQueue:self.executor.workQueue fmap:^(FBFuture<NSNumber *> *exitCode) {
      return [FBListTestStrategy
        launchedProcessWithExitCode:exitCode
        shimOutput:shimOutput
        shimBuffer:shimBuffer
        stdOutBuffer:stdOutBuffer
        stdErrBuffer:stdErrBuffer
        queue:self.executor.workQueue];
    }];
}

+ (FBFuture<NSArray<NSString *> *> *)launchedProcessWithExitCode:(FBFuture<NSNumber *> *)exitCode shimOutput:(id<FBProcessFileOutput>)shimOutput shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer queue:(dispatch_queue_t)queue
{
  return [[[shimOutput
    startReading]
    onQueue:queue fmap:^(id _) {
      return [FBListTestStrategy
        onQueue:queue
        confirmExit:exitCode
        closingOutput:shimOutput
        shimBuffer:shimBuffer
        stdOutBuffer:stdOutBuffer
        stdErrBuffer:stdErrBuffer];
    }]
    onQueue:queue fmap:^(id _) {
      NSError *error = nil;
      NSArray<NSDictionary<NSString *, NSString *> *> *tests = [NSJSONSerialization JSONObjectWithData:shimBuffer.data options:0 error:&error];
      if (!tests) {
        return [FBFuture futureWithError:error];
      }
      NSMutableArray<NSString *> *testNames = [NSMutableArray array];
      for (NSDictionary<NSString *, NSString *> * test in tests) {
        NSString *testName = test[kReporter_ListTest_LegacyTestNameKey];
        if (![testName isKindOfClass:NSString.class]) {
          return [[FBXCTestError
            describeFormat:@"Received unexpected test name from shim: %@", testName]
            failFuture];
        }
        [testNames addObject:testName];
      }
      return [FBFuture futureWithResult:[testNames copy]];
  }];
}

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue confirmExit:(FBFuture<NSNumber *> *)exitCode closingOutput:(id<FBProcessFileOutput>)output shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer
{
  return [exitCode
    onQueue:queue fmap:^(NSNumber *exitCodeNumber) {
      int exitCodeValue = exitCodeNumber.intValue;
      NSString *descriptionOfFailingExit = [FBXCTestProcess describeFailingExitCode:exitCodeValue];
      if (descriptionOfFailingExit) {
        NSString *stdErrReversed = [stdErrBuffer.lines.reverseObjectEnumerator.allObjects componentsJoinedByString:@"\n"];
        return [[XCTestBootstrapError
          describeFormat:@"Listing of tests failed due to xctest binary exiting with non-zero exit code %d [%@]: %@", exitCodeValue, descriptionOfFailingExit, stdErrReversed]
          failFuture];
      }
      return [FBFuture futureWithFutures:@[
        [output stopReading],
        [shimBuffer finishedConsuming],
      ]];
    }];
}

+ (FBFuture<FBFuture<NSNumber *> *> *)listTestProcessWithConfiguration:(FBListTestConfiguration *)configuration environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor logger:(id<FBControlCoreLogger>)logger
{
  NSString *launchPath = executor.xctestPath;
  NSInteger timeout = 20;

  // List test for app test bundle, so we use app binary instead of xctest to load test bundle.
  if ([FBBundleDescriptor isApplicationAtPath:configuration.runnerAppPath]) {
    NSString *xcTestFrameworkPath =
    [[FBXcodeConfiguration.developerDirectory
      stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform"]
      stringByAppendingPathComponent:@"Developer/Library/Frameworks/XCTest.framework"];

    // Since we spawn process using app binary directly without installation, we need to manully copy
    // xctest framework to app's rpath so it can be found by dyld when we load test bundle later.
    [self copyFrameworkToApplicationAtPath:configuration.runnerAppPath frameworkPath:xcTestFrameworkPath error:nil];

    // Since Xcode 11, XCTest.framework load XCTAutomationSupport.framework use LC_LOAD_DYLIB, so
    // we need to make sure XCTAutomationSupport.framework is available at @rpath when we load test bundle.
    if ([FBXcodeConfiguration.xcodeVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"11.0"]]) {
      NSString *XCTAutomationSupportFrameworkPath =
      [[FBXcodeConfiguration.developerDirectory
        stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform"]
        stringByAppendingPathComponent:@"Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework"];

      [self copyFrameworkToApplicationAtPath:configuration.runnerAppPath frameworkPath:XCTAutomationSupportFrameworkPath error:nil];
    }

    FBBundleDescriptor *appBundle = [FBBundleDescriptor bundleFromPath:configuration.runnerAppPath error:nil];
    launchPath = appBundle.binary.path;
    // Launching large binary like Facebook app could take a while.
    timeout = 60;
  }

  return [[executor
    startProcessWithLaunchPath:launchPath
    arguments:@[]
    environment:environment
    stdOutConsumer:stdOutConsumer
    stdErrConsumer:stdErrConsumer]
    onQueue:executor.workQueue map:^(id<FBLaunchedProcess> process) {
      return [FBXCTestProcess ensureProcess:process completesWithin:timeout queue:executor.workQueue logger:logger];
    }];
}

+ (NSString *)copyFrameworkToApplicationAtPath:(NSString *)appPath frameworkPath:(NSString *)frameworkPath error:(NSError **)error
{
  if (![FBBundleDescriptor isApplicationAtPath:appPath]) {
    return nil;
  }

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSString *frameworksDir = [appPath stringByAppendingPathComponent:@"Frameworks"];
  BOOL isDirectory = NO;
  if ([fileManager fileExistsAtPath:frameworksDir isDirectory:&isDirectory]) {
    if (!isDirectory) {
      return [[FBControlCoreError
        describeFormat:@"%@ is not a directory", frameworksDir]
        fail:error];
    }
  } else {
    if (![fileManager createDirectoryAtPath:frameworksDir withIntermediateDirectories:NO attributes:nil error:error]) {
      return [[FBControlCoreError
        describeFormat:@"Create framework directory %@ failed", frameworksDir]
        fail:error];
    }
  }

  NSString *toPath = [frameworksDir stringByAppendingPathComponent:[frameworkPath lastPathComponent]];
  if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
    return appPath;
  }

  if (![fileManager copyItemAtPath:frameworkPath toPath:toPath error:error]) {
    return [[FBControlCoreError
      describeFormat:@"Error copying framework %@ to app %@.", frameworkPath, appPath]
      fail:error];
  }

  return appPath;
}

- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter
{
  return [[FBListTestStrategy_ReporterWrapped alloc] initWithStrategy:self reporter:reporter];
}

@end
