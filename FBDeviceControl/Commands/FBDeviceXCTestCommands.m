/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
@property (nonatomic, assign, readwrite) BOOL runningXcodeBuildOperation;

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

- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  // Return early and fail if there is already a test run for the device.
  // There should only ever be one test run per-device.
  if (self.runningXcodeBuildOperation) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot Start Test Manager with Configuration %@ as it is already running", testLaunchConfiguration]
      failFuture];
  }
  // Terminate the reparented xcodebuild invocations.
  return [[[[FBXcodeBuildOperation
    terminateAbandonedXcodebuildProcessesForUDID:self.device.udid processFetcher:self.processFetcher queue:self.device.workQueue logger:logger]
    onQueue:self.device.workQueue fmap:^(id _) {
      self.runningXcodeBuildOperation = YES;
      // Then start the task. This future will yield when the task has *started*.
      return [self _startTestWithLaunchConfiguration:testLaunchConfiguration logger:logger];
    }]
    onQueue:self.device.workQueue fmap:^(FBProcess *task) {
      // Then wrap the started task, so that we can augment it with logging and adapt it to the FBiOSTargetOperation interface.
      return [FBXcodeBuildOperation confirmExitOfXcodebuildOperation:task configuration:testLaunchConfiguration reporter:reporter target:self.device logger:logger];
    }]
    onQueue:self.device.workQueue chain:^(FBFuture *future) {
      self.runningXcodeBuildOperation = NO;
      return future;
    }];
}

#pragma mark Private

- (FBFuture<FBProcess *> *)_startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
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

  // This is to walk around a bug in xcodebuild. The UDID inside xcodebuild does not match
  // UDID reported by device properties (the difference is missing hyphen in xcodebuild).
  // This results in xcodebuild returning an error, since it cannot find a device with requested
  // id (e.g. we query for 00008101-001D296A2EE8001E, while xcodebuild have
  // 00008101001D296A2EE8001E).
  NSString *udid = (__bridge NSString *)self.device.calls.CopyDeviceIdentifier(self.device.amDeviceRef);

  // Create the Task, wrap it and store it.
  return [FBXcodeBuildOperation
    operationWithUDID:udid
    configuration:configuration
    xcodeBuildPath:xcodeBuildPath
    testRunFilePath:filePath
    simDeviceSet:nil
    macOSTestShimPath:nil
    queue:self.device.workQueue
    logger:[logger withName:@"xcodebuild"]];
}

@end
