/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager+XCTest.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

#import "FBIDBStorageManager.h"
#import "FBIDBError.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"
#import "FBXCTestDescriptor.h"

static const NSTimeInterval DEFAULT_CLIENT_TIMEOUT = 60;
static const NSTimeInterval FBLogicTestTimeout = 60 * 60; //Aprox. an hour.

@interface FBXCTestDelta ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

@end

@implementation FBXCTestDelta

- (instancetype)initWithIdentifier:(NSString *)identifier results:(NSArray<FBTestRunUpdate *> *)results logOutput:(NSString *)logOutput resultBundlePath:(NSString *)resultBundlePath state:(FBIDBTestManagerState)state error:(NSError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identifier = identifier;
  _results = results;
  _logOutput = logOutput;
  _resultBundlePath = resultBundlePath;
  _state = state;
  _error = error;

  return self;
}

@end

@interface FBIDBTestOperation ()

@property (nonatomic, strong, readonly) id<FBJSONSerializable> configuration;
@property (nonatomic, strong, readonly) FBConsumableXCTestReporter *reporter;
@property (nonatomic, strong, readonly) id<FBConsumableBuffer> logBuffer;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, readonly) NSString *resultBundlePath;

@end

@implementation FBIDBTestOperation

@synthesize completed = _completed;

- (instancetype)initWithConfiguration:(id<FBJSONSerializable>)configuration resultBundlePath:(NSString *)resultBundlePath reporter:(FBConsumableXCTestReporter *)reporter logBuffer:(id<FBConsumableBuffer>)logBuffer completed:(FBFuture<NSNull *> *)completed queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _resultBundlePath = resultBundlePath;
  _reporter = reporter;
  _logBuffer = logBuffer;
  _completed = completed;
  _queue = queue;

  return self;
}

- (FBIDBTestManagerState)state
{
  if (self.completed) {
    if (self.completed.error) {
      return FBIDBTestManagerStateTerminatedAbnormally;
    } else {
      return self.completed.hasCompleted ? FBIDBTestManagerStateTerminatedNormally : FBIDBTestManagerStateRunning;
    }
  } else {
    return FBIDBTestManagerStateNotRunning;
  }
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Test Run (%@)", self.configuration.jsonSerializableRepresentation];
}

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeTestOperation;
}

@end

@interface FBFuture (FBIDBTestManager)

- (instancetype)idb_appendErrorLogging:(FBIDBTestOperation *)operation;

@end

@implementation FBFuture (FBIDBTestManager)

- (instancetype)idb_appendErrorLogging:(FBIDBTestOperation *)operation
{
  return [self onQueue:operation.queue chain:^(FBFuture *future) {
    if (!future.error) {
      return future;
    }
    return [[FBIDBError
      describeFormat:@"%@:%@", future.error.localizedDescription, operation.logBuffer.lines]
      failFuture];
  }];
}

@end

@implementation FBDeltaUpdateManager (XCTest)

#pragma mark Initializers

+ (FBXCTestDeltaUpdateManager *)xctestManagerWithTarget:(id<FBiOSTarget>)target bundleStorage:(FBXCTestBundleStorage *)bundleStorage temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [self
    managerWithTarget:target
    name:@"xctest"
    expiration:@(DEFAULT_CLIENT_TIMEOUT)
    capacity:nil
    logger:target.logger
    create:^ FBFuture<FBIDBTestOperation *> * (FBXCTestRunRequest *request) {
      return [[self
        fetchAndSetupDescriptorForRequest:request bundleStorage:bundleStorage target:target]
        onQueue:target.workQueue fmap:^(id<FBXCTestDescriptor> descriptor) {
          if (request.isLogicTest) {
            return [self startLogicTest:request testDescriptor:descriptor target:target temporaryDirectory:temporaryDirectory];
          } else {
            return [self startApplicationBasedTest:request testDescriptor:descriptor target:target];
          }
        }];
    }
    delta:^(FBIDBTestOperation *operation, NSString *identifier, BOOL *done) {
      FBIDBTestManagerState state = operation.state;
      NSString *logOutput = [operation.logBuffer consumeCurrentString];
      NSString *resultBundlePath = operation.resultBundlePath;
      NSError *error = operation.completed.error;
      NSArray<FBTestRunUpdate *> *results = [operation.reporter consumeCurrentResults];
      if (state == FBIDBTestManagerStateTerminatedNormally) {
        *done = YES;
      }

      FBXCTestDelta *delta = [[FBXCTestDelta alloc]
        initWithIdentifier:identifier
        results:results
        logOutput:logOutput
        resultBundlePath:resultBundlePath
        state:state
        error:error];

      return [FBFuture futureWithResult:delta];
    }];
}

#pragma mark Private Methods

+ (FBFuture<id<FBXCTestDescriptor>> *)fetchAndSetupDescriptorForRequest:(FBXCTestRunRequest *)request bundleStorage:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target
{
  NSError *error = nil;
  id<FBXCTestDescriptor> testDescriptor = [bundleStorage testDescriptorWithID:request.testBundleID error:&error];
  if (!testDescriptor) {
    return [FBFuture futureWithError:error];
  }
  return [[testDescriptor setupWithRequest:request target:target] mapReplace:testDescriptor];
}

+ (FBFuture<id<FBXCTestProcessExecutor>> *)executorWithConfiguration:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  id<FBXCTestProcessExecutor> executor = nil;
  if ([target isKindOfClass:FBSimulator.class]) {
    executor = [FBSimulatorXCTestProcessExecutor executorWithSimulator:(FBSimulator *)target shims:configuration.shims];
  } else if ([target isKindOfClass:FBMacDevice.class]) {
    executor = [FBMacXCTestProcessExecutor executorWithMacDevice:(FBMacDevice *)target shims:configuration.shims];
  }

  if (!executor) {
    return [[FBIDBError
      describeFormat:@"%@ does not support logic tests", target]
      failFuture];
  }
  return [FBFuture futureWithResult:executor];
}

+ (FBFuture<FBIDBTestOperation *> *)runLogic:(FBLogicTestConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  return [[self
    executorWithConfiguration:configuration target:target]
    onQueue:target.workQueue fmap:^(id<FBXCTestProcessExecutor> executor) {
      id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
      id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:logBuffer];
      FBConsumableXCTestReporter *reporter = [FBConsumableXCTestReporter new];
      FBLogicReporterAdapter *adapter = [[FBLogicReporterAdapter alloc] initWithReporter:reporter logger:logger];
      FBLogicTestRunStrategy *runner = [FBLogicTestRunStrategy strategyWithExecutor:executor configuration:configuration reporter:adapter logger:logger];
      FBFuture<NSNull *> *completed = [runner execute];
      if (completed.error) {
        return [FBFuture futureWithError:completed.error];
      }
      FBIDBTestOperation *operation = [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:nil reporter:reporter logBuffer:logBuffer completed:completed queue:target.workQueue];
      return [[FBFuture futureWithResult:operation] idb_appendErrorLogging:operation];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)run:(FBTestLaunchConfiguration *)configuration target:(id<FBiOSTarget>)target
{
  id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:logBuffer];
  FBConsumableXCTestReporter *reporter = [FBConsumableXCTestReporter new];
  FBXCTestReporterAdapter *adapter = [FBXCTestReporterAdapter adapterWithReporter:reporter];
  return [[target
    startTestWithLaunchConfiguration:configuration reporter:adapter logger:logger]
    onQueue:target.workQueue fmap:^(id<FBiOSTargetContinuation> continuation) {
      FBIDBTestOperation *operation = [[FBIDBTestOperation alloc] initWithConfiguration:configuration resultBundlePath:configuration.resultBundlePath reporter:reporter logBuffer:logBuffer completed:continuation.completed queue:target.workQueue];
      return [[FBFuture futureWithResult:operation] idb_appendErrorLogging:operation];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)startLogicTest:(FBXCTestRunRequest *)request testDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory
{
  return [[FBXCTestShimConfiguration
    defaultShimConfiguration]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBXCTestShimConfiguration *shims) {
      NSError *error = nil;
      NSURL *workingDirectory = [temporaryDirectory ephemeralTemporaryDirectory];
      if (![NSFileManager.defaultManager createDirectoryAtURL:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [FBFuture futureWithError:error];
      }
      NSString *testFilter = nil;
      NSArray<NSString *> *testsToSkip = request.testsToSkip.allObjects ?: @[];
      if (testsToSkip.count > 0) {
        return [[FBXCTestError
          describeFormat:@"'Tests to Skip' %@ provided, but Logic Tests to not support this.", [FBCollectionInformation oneLineDescriptionFromArray:testsToSkip]]
          failFuture];
      }
      NSArray<NSString *> *testsToRun = request.testsToRun.allObjects ?: @[];
      if (testsToRun.count > 1){
        return [[FBXCTestError
          describeFormat:@"More than one 'Tests to Run' %@ provided, but only one 'Tests to Run' is supported.", [FBCollectionInformation oneLineDescriptionFromArray:testsToRun]]
          failFuture];
      }
      testFilter = testsToRun.firstObject;

      NSTimeInterval timeout = request.testTimeout.boolValue ? request.testTimeout.doubleValue : FBLogicTestTimeout;
      FBLogicTestConfiguration *configuration = [FBLogicTestConfiguration
        configurationWithShims:shims
        environment:request.environment
        workingDirectory:workingDirectory.path
        testBundlePath:testDescriptor.testBundle.path
        waitForDebugger:NO
        timeout:timeout
        testFilter:testFilter
        mirroring:FBLogicTestMirrorFileLogs];

      return [self runLogic:configuration target:target];
    }];
}

+ (FBFuture<FBIDBTestOperation *> *)startApplicationBasedTest:(FBXCTestRunRequest *)request testDescriptor:(id<FBXCTestDescriptor>)testDescriptor target:(id<FBiOSTarget>)target
{
  return [[testDescriptor
    testAppPairForRequest:request target:target]
    onQueue:target.workQueue fmap:^ FBFuture<FBIDBTestOperation *> * (FBTestApplicationsPair *pair) {
      [target.logger logFormat:@"Obtaining launch configuration for App Pair %@ on descriptor %@", pair, testDescriptor];
      FBTestLaunchConfiguration *testConfig = [testDescriptor testConfigWithRunRequest:request testApps:pair];
      [target.logger logFormat:@"Obtained launch configuration %@", testConfig];
      return [self run:testConfig target:target];
    }];
}

@end
