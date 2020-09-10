/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBCollectionInformation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceXCTestCommands.h"
#import "FBAMDServiceConnection.h"

@interface FBDeviceXCTestCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readwrite) id<FBiOSTargetContinuation> operation;

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

#pragma mark FBXCTestCommands Implementation

- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  // Return early and fail if there is already a test run for the device.
  // There should only ever be one test run per-device.
  if (self.operation) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
      failFuture];
  }
  // Terminate the reparented xcodebuild invocations.
  return [[[FBXcodeBuildOperation
    terminateAbandonedXcodebuildProcessesForUDID:self.device.udid processFetcher:self.processFetcher queue:self.device.workQueue logger:logger]
    onQueue:self.device.workQueue fmap:^(id _) {
      // Then start the task. This future will yield when the task has *started*.
      return [self _startTestWithLaunchConfiguration:testLaunchConfiguration logger:logger];
    }]
    onQueue:self.device.workQueue map:^(FBTask *task) {
      // Then wrap the started task, so that we can augment it with logging and adapt it to the FBiOSTargetContinuation interface.
      return [self _testOperationStarted:task configuration:testLaunchConfiguration reporter:reporter logger:logger];
    }];
}

- (NSArray<id<FBiOSTargetContinuation>> *)testOperations
{
  id<FBiOSTargetContinuation> operation = self.operation;
  return operation ? @[operation] : @[];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(nonnull NSString *)appPath
{
  return [[FBDeviceControlError
    describeFormat:@"Cannot list the tests in bundle %@ as this is not supported on devices", bundlePath]
    failFuture];
}

- (FBFutureContext<NSNumber *> *)transportForTestManagerService
{
  return [[self.device
    startService:@"com.apple.testmanagerd.lockdown"]
    onQueue:self.device.workQueue pend:^(FBAMDServiceConnection *connection) {
      return [FBFuture futureWithResult:@(connection.socket)];
    }];
}

#pragma mark Private

- (FBFuture<FBTask *> *)_startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  // Create the .xctestrun file
  NSString *filePath = [FBXcodeBuildOperation createXCTestRunFileAt:self.workingDirectory fromConfiguration:configuration error:&error];
  if (!filePath) {
    return [FBDeviceControlError failFutureWithError:error];
  }

  // Find the path to xcodebuild
  NSString *xcodeBuildPath = [FBXcodeBuildOperation xcodeBuildPathWithError:&error];
  if (!xcodeBuildPath) {
    return [FBDeviceControlError failFutureWithError:error];
  }

  // Create the Task, wrap it and store it.
  return [FBXcodeBuildOperation
    operationWithUDID:self.device.udid
    configuration:configuration
    xcodeBuildPath:xcodeBuildPath
    testRunFilePath:filePath
    queue:self.device.workQueue
    logger:[logger withName:@"xcodebuild"]];
}

- (id<FBiOSTargetContinuation>)_testOperationStarted:(FBTask *)task configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNull *> *completed = [[[[task
    completed]
    onQueue:self.device.workQueue fmap:^FBFuture<NSNull *> *(id _) {
      // This will execute only if the operation completes successfully.
      [logger logFormat:@"xcodebuild operation completed successfully %@", task];
      if (configuration.resultBundlePath) {
        return [FBXCTestResultBundleParser parse:configuration.resultBundlePath target:self.device reporter:reporter logger:logger];
      }
      [logger log:@"No result bundle to parse"];
      return FBFuture.empty;
    }]
    onQueue:self.device.workQueue fmap:^(id _) {
      [logger log:@"Reporting test results"];
      [reporter testManagerMediatorDidFinishExecutingTestPlan:nil];
      return FBFuture.empty;
    }]
    onQueue:self.device.workQueue chain:^(FBFuture *future) {
      // Always perform this, whether the operation was successful or not.
      [logger logFormat:@"Test Operation has completed for %@, with state '%@' removing it as the sole operation for this target", future, configuration.shortDescription];
      self.operation = nil;
      return future;
    }];

  self.operation = FBiOSTargetContinuationNamed(completed, FBiOSTargetFutureTypeTestOperation);
  [logger logFormat:@"Test Operation %@ has started for %@, storing it as the sole operation for this target", task, configuration.shortDescription];

  return self.operation;
}

@end
