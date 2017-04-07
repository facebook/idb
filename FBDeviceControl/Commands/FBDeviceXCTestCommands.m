/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBControlCore.h>

#import "FBDevice.h"
#import "FBDeviceXCTestCommands.h"
#import "FBDeviceControlError.h"

static NSString *XcodebuildSubprocessEnvironmentIdentifier = @"FBDEVICECONTROL_DEVICE_IDENTIFIER";

@interface FBDeviceXCTestCommands_TestOperation : NSObject <FBXCTestOperation>

@property (nonatomic, strong, nullable, readonly) FBTask *task;

@end

@implementation FBDeviceXCTestCommands_TestOperation

- (instancetype)initWithTask:(FBTask *)task
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;

  return self;
}

- (FBTerminationHandleType)type
{
  return FBTerminationHandleTypeTestOperation;
}

- (void)terminate
{
  [self.task terminate];
  _task = nil;
}

- (BOOL)hasTerminated
{
  return self.task.hasTerminated || self.task == nil;
}

@end

@interface FBDeviceXCTestCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;
@property (nonatomic, strong, nullable, readonly) FBDeviceXCTestCommands_TestOperation *operation;

@end

@implementation FBDeviceXCTestCommands

+ (instancetype)commandsWithDevice:(FBDevice *)device
{
  return [[self alloc] initWithDevice:device];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _processFetcher = [FBProcessFetcher new];

  return self;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch
{
  return @{
    @"StubBundleId" : @{
      @"TestHostPath" : testLaunch.testHostPath,
      @"TestBundlePath" : testLaunch.testBundlePath,
      @"UseUITargetAppProvidedByTests" : @YES,
      @"IsUITestBundle" : @YES,
      @"CommandLineArguments": testLaunch.applicationLaunchConfiguration.arguments,
      @"TestingEnvironmentVariables": @{
            @"DYLD_FRAMEWORK_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
            @"DYLD_LIBRARY_PATH": @"__TESTROOT__:__PLATFORMS__/iPhoneOS.platform/Developer/Library/Frameworks",
      },
    }
  };
}

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
  if (![FBDeviceXCTestCommands terminateReparentedXcodeBuildProcessesForDevice:self.device processFetcher:self.processFetcher error:&innerError]) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Create the .xctestrun file
  NSString *filePath = [FBDeviceXCTestCommands createXCTestRunFileFromConfiguration:testLaunchConfiguration forDevice:self.device error:&innerError];
  if (!filePath) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Find the path to xcodebuild
  NSString *xcodeBuildPath = [FBDeviceXCTestCommands xcodeBuildPathWithError:&innerError];
  if (!xcodeBuildPath) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Create the Task, wrap it and store it
  FBTask *task = [FBDeviceXCTestCommands createTask:testLaunchConfiguration xcodeBuildPath:xcodeBuildPath testRunFilePath:filePath device:self.device];
  [task startAsynchronously];
  _operation = [[FBDeviceXCTestCommands_TestOperation alloc] initWithTask:task];

  return _operation;
}

- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (!self.operation) {
    return YES;
  }
  NSError *innerError = nil;
  if (![self.operation.task waitForCompletionWithTimeout:timeout error:&innerError]) {
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

+ (nullable NSString *)createXCTestRunFileFromConfiguration:(FBTestLaunchConfiguration *)configuration forDevice:(FBDevice *)device error:(NSError **)error
{
  NSString *tmp = NSTemporaryDirectory();
  NSString *fileName = [NSProcessInfo.processInfo.globallyUniqueString stringByAppendingPathExtension:@"xctestrun"];
  NSString *path = [tmp stringByAppendingPathComponent:fileName];

  NSDictionary *testRunProperties = [self xctestRunProperties:configuration];
  if (![testRunProperties writeToFile:path atomically:false]) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to write to file %@", path]
      fail:error];
  }
  return path;
}

+ (NSString *)xcodeBuildPathWithError:(NSError **)error
{
  NSString *path = [FBControlCoreGlobalConfiguration.developerDirectory stringByAppendingPathComponent:@"/usr/bin/xcodebuild"];
  if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
    return [[FBDeviceControlError
      describeFormat:@"xcodebuild does not exist at expected path %@", path]
      fail:error];
  }
  return path;
}

+ (FBTask *)createTask:(FBTestLaunchConfiguration *)configuraton xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath device:(FBDevice *)device
{

  NSArray<NSString *> *arguments = @[
    @"test-without-building",
    @"-xctestrun", testRunFilePath,
    @"-destination", [NSString stringWithFormat:@"id=%@", device.udid],
  ];

  NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
  environment[XcodebuildSubprocessEnvironmentIdentifier] = device.udid;

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:xcodeBuildPath arguments:arguments]
    withEnvironment:environment]
    withStdOutToLogger:device.logger]
    withStdErrToLogger:device.logger]
    build];

  return task;
}

+ (BOOL)terminateReparentedXcodeBuildProcessesForDevice:(FBDevice *)device processFetcher:(FBProcessFetcher *)processFetcher error:(NSError **)error
{
  NSArray<FBProcessInfo *> *processes = [processFetcher processesWithProcessName:@"xcodebuild"];
  FBProcessTerminationStrategy *strategy = [FBProcessTerminationStrategy strategyWithProcessFetcher:processFetcher logger:device.logger];
  NSString *udid = device.udid;
  for (FBProcessInfo *process in processes) {
    if (![process.environment[XcodebuildSubprocessEnvironmentIdentifier] isEqualToString:udid]) {
      continue;
    }
    if (![strategy killProcess:process error:error]) {
      return NO;
    }
  }
  return YES;
}

@end
