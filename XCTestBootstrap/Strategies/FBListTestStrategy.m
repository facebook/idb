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
  id<FBConsumableBuffer> shimConsumer = [FBDataBuffer consumableBuffer];
  return [[[FBProcessOutput
    outputForDataConsumer:shimConsumer]
    providedThroughFile]
    onQueue:self.executor.workQueue fmap:^(id<FBProcessFileOutput> shimOutput) {
      return [self listTestsWithShimOutput:shimOutput shimConsumer:shimConsumer];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<NSString *> *> *)listTestsWithShimOutput:(id<FBProcessFileOutput>)shimOutput shimConsumer:(id<FBConsumableBuffer>)shimConsumer
{
  NSDictionary<NSString *, NSString *> *environment = @{
    @"DYLD_INSERT_LIBRARIES": self.executor.shimPath,
    @"TEST_SHIM_OUTPUT_PATH": shimOutput.filePath,
    @"TEST_SHIM_BUNDLE_PATH": self.configuration.testBundlePath,
  };

  return [[self.configuration
    listTestProcessWithEnvironment:environment
    stdOutConsumer:[FBLoggingDataConsumer consumerWithLogger:self.logger]
    stdErrConsumer:[FBLoggingDataConsumer consumerWithLogger:self.logger]
    executor:self.executor
    logger:self.logger]
    onQueue:self.executor.workQueue fmap:^(id<FBLaunchedProcess> processInfo) {
      return [FBListTestStrategy launchedProcess:processInfo shimOutput:shimOutput shimConsumer:shimConsumer queue:self.executor.workQueue];
    }];
}

+ (FBFuture<NSArray<NSString *> *> *)launchedProcess:(id<FBLaunchedProcess>)processInfo shimOutput:(id<FBProcessFileOutput>)shimOutput shimConsumer:(id<FBConsumableBuffer>)shimConsumer queue:(dispatch_queue_t)queue
{
  return [[[shimOutput
    startReading]
    onQueue:queue fmap:^(id _) {
      return [FBListTestStrategy onQueue:queue confirmExit:processInfo closingOutput:shimOutput consumer:shimConsumer];
    }]
    onQueue:queue fmap:^(id _) {
      NSError *error = nil;
      NSArray<NSDictionary<NSString *, NSString *> *> *tests = [NSJSONSerialization JSONObjectWithData:shimConsumer.data options:0 error:&error];
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

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue confirmExit:(id<FBLaunchedProcess>)process closingOutput:(id<FBProcessFileOutput>)output consumer:(id<FBConsumableBuffer>)consumer
{
  return [process.exitCode onQueue:queue fmap:^(NSNumber *exitCode) {
    if (exitCode.intValue != 0) {
      return [[XCTestBootstrapError
        describeFormat:@"Process %d Exited with non-zero %@", process.processIdentifier, exitCode]
        failFuture];
    }
    return [FBFuture futureWithFutures:@[
      [output stopReading],
      [consumer finishedConsuming],
    ]];
  }];
}

- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter
{
  return [[FBListTestStrategy_ReporterWrapped alloc] initWithStrategy:self reporter:reporter];
}

@end
