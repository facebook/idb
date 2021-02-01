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

  return [[self.configuration
    listTestProcessWithEnvironment:environment
    stdOutConsumer:stdOutConsumer
    stdErrConsumer:stdErrConsumer
    executor:self.executor
    logger:self.logger]
    onQueue:self.executor.workQueue fmap:^(FBXCTestProcess *process) {
      return [FBListTestStrategy
        launchedProcess:process
        shimOutput:shimOutput
        shimBuffer:shimBuffer
        stdOutBuffer:stdOutBuffer
        stdErrBuffer:stdErrBuffer
        queue:self.executor.workQueue];
    }];
}

+ (FBFuture<NSArray<NSString *> *> *)launchedProcess:(FBXCTestProcess *)process shimOutput:(id<FBProcessFileOutput>)shimOutput shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer queue:(dispatch_queue_t)queue
{
  return [[[shimOutput
    startReading]
    onQueue:queue fmap:^(id _) {
      return [FBListTestStrategy
        onQueue:queue
        confirmExit:process
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

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue confirmExit:(FBXCTestProcess *)process closingOutput:(id<FBProcessFileOutput>)output shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer
{
  return [process.exitCode
    onQueue:queue fmap:^(NSNumber *exitCode) {
      if (exitCode.intValue != 0) {
        return [[XCTestBootstrapError
          describeFormat:@"Listing of tests failed due to xctest binary exiting with non-zero exit code %@. (%@%@)", exitCode, stdOutBuffer.consumeCurrentString, stdErrBuffer.consumeCurrentString]
          failFuture];
      }
      return [FBFuture futureWithFutures:@[
        [output stopReading],
        [shimBuffer finishedConsuming],
      ]];
    }];
}

- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter
{
  return [[FBListTestStrategy_ReporterWrapped alloc] initWithStrategy:self reporter:reporter];
}

@end
