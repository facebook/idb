/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorServiceContext.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceSet+Removed.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimDeviceType+Removed.h>
#import <CoreSimulator/SimRuntime.h>
#import <CoreSimulator/SimRuntime+Removed.h>
#import <CoreSimulator/SimServiceContext.h>

#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorServiceContext ()

@property (nonatomic, strong, readonly) SimServiceContext *serviceContext;

- (instancetype)initWithServiceContext:(SimServiceContext *)serviceContext;

@end

@implementation FBSimulatorServiceContext

#pragma mark Initialization

+ (instancetype)sharedServiceContext
{
  static dispatch_once_t onceToken;
  static FBSimulatorServiceContext *serviceContext = nil;
  dispatch_once(&onceToken, ^{
    serviceContext = [self createServiceContext];
  });
  return serviceContext;
}

+ (instancetype)createServiceContext
{
  Class serviceContextClass = objc_lookUpClass("SimServiceContext");
  NSAssert([serviceContextClass respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)], @"Service Context cannot be instantiated");
  NSError *innerError = nil;
  SimServiceContext *serviceContext = [serviceContextClass sharedServiceContextForDeveloperDir:FBXcodeConfiguration.developerDirectory error:&innerError];
  NSAssert(serviceContext, @"Could not create a service context with error %@", innerError);
  return [[FBSimulatorServiceContext alloc] initWithServiceContext:serviceContext];
}

- (instancetype)initWithServiceContext:(SimServiceContext *)serviceContext
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _serviceContext = serviceContext;

  return self;
}

#pragma mark Public

- (NSArray<NSString *> *)pathsOfAllDeviceSets
{
  NSMutableArray<NSString *> *deviceSetPaths = [NSMutableArray array];
  for (SimDeviceSet *deviceSet in self.serviceContext.allDeviceSets) {
    [deviceSetPaths addObject:deviceSet.setPath];
  }
  return deviceSetPaths;
}

- (NSArray<SimRuntime *> *)supportedRuntimes
{
  return [self.serviceContext supportedRuntimes];
}

- (NSArray<SimDeviceType *> *)supportedDeviceTypes
{
  return [self.serviceContext supportedDeviceTypes];
}

- (SimDeviceSet *)createDeviceSetWithConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  NSError *innerError = nil;
  NSString *deviceSetPath = configuration.deviceSetPath;
  if (deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to create custom SimDeviceSet directory at %@", deviceSetPath]
        causedBy:innerError]
        fail:error];
    }
  }

  SimDeviceSet *deviceSet = [self createUnderlyingDeviceSet:deviceSetPath error:&innerError];
  if (!deviceSet) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create underlying device set for configuration %@", configuration]
      causedBy:innerError]
      fail:error];
  }
  return deviceSet;
}

#pragma mark Private

- (SimDeviceSet *)createUnderlyingDeviceSet:(NSString *)deviceSetPath error:(NSError **)error
{
  return deviceSetPath
    ? [self.serviceContext deviceSetWithPath:deviceSetPath error:error]
    : [self.serviceContext defaultDeviceSetWithError:error];
}

@end
