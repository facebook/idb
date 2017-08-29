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

- (id<FBXCTestOperation>)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration error:(NSError **)error
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

  return _operation;
}

- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (!self.operation) {
    return YES;
  }
  NSError *innerError = nil;
  if (![self.operation waitForCompletionWithTimeout:timeout error:&innerError]) {
    [self.operation terminate];
    _operation = nil;
    return [[[FBDeviceControlError
      describe:@"Failed waiting for timeout"]
      causedBy:innerError]
      failBool:error];
  }
  _operation = nil;
  return YES;
}

- (NSArray<NSString *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [[FBDeviceControlError
    describeFormat:@"Cannot list the tests in bundle %@ as this is not supported on devices", bundlePath]
    fail:error];
}

#pragma mark Private

- (nullable NSString *)createXCTestRunFileFromConfiguration:(FBTestLaunchConfiguration *)configuration error:(NSError **)error
{
  NSString *fileName = [NSProcessInfo.processInfo.globallyUniqueString stringByAppendingPathExtension:@"xctestrun"];
  NSString *path = [self.workingDirectory stringByAppendingPathComponent:fileName];

  NSDictionary *testRunProperties = [FBXcodeBuildOperation xctestRunProperties:configuration];
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
