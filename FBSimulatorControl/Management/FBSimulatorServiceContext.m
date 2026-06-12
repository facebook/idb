/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@interface FBSimulatorServiceContext ()

@property (nonatomic, strong, readonly) SimServiceContext *serviceContext;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

- (instancetype)initWithServiceContext:(SimServiceContext *)serviceContext;

@end

@implementation FBSimulatorServiceContext

#pragma mark Initialization Public

+ (instancetype)sharedServiceContext
{
  return [self sharedServiceContextWithLogger:FBControlCoreGlobalConfiguration.defaultLogger];
}

+ (instancetype)sharedServiceContextWithLogger:(id<FBControlCoreLogger>)logger
{
  // CoreSimulator's `sharedServiceContextForDeveloperDir:` vends one context
  // per developer directory. Cache per directory (instead of a single
  // process-lifetime instance) so hosts that switch Xcode at runtime get a
  // context for the newly selected developer directory without a restart.
  static dispatch_once_t onceToken;
  static NSMutableDictionary<NSString *, FBSimulatorServiceContext *> *serviceContexts = nil;
  dispatch_once(&onceToken, ^{
    serviceContexts = [NSMutableDictionary dictionary];
  });
  NSString *developerDirectory = [FBXcodeConfiguration getDeveloperDirectoryIfExists] ?: @"";
  @synchronized (serviceContexts) {
    FBSimulatorServiceContext *serviceContext = serviceContexts[developerDirectory];
    if (!serviceContext) {
      serviceContext = [self createServiceContextWithLogger:logger];
      serviceContexts[developerDirectory] = serviceContext;
    }
    return serviceContext;
  }
}

#pragma mark Initialization Private

+ (instancetype)createServiceContextWithLogger:(id<FBControlCoreLogger>)logger
{
  Class serviceContextClass = objc_lookUpClass("SimServiceContext");
  NSAssert([serviceContextClass respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)], @"Service Context cannot be instantiated");
  NSError *innerError = nil;
  NSXPCConnection *conn = [[NSXPCConnection alloc] initWithServiceName:@"com.apple.CoreSimulator.CoreSimulatorService"];
  if (@available(macOS 11.0, *)) {
      [conn activate];
  }

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
  NSString *deviceSetPath = configuration.deviceSetPath;
  if (!deviceSetPath) {
    return [self.serviceContext defaultDeviceSetWithError:error];
  }
  deviceSetPath = [FBSimulatorServiceContext fullyQualifiedDeviceSetPath:configuration.deviceSetPath error:error];
  if (!deviceSetPath) {
    return nil;
  }
  NSError *innerError = nil;
  SimDeviceSet *deviceSet = [self.serviceContext deviceSetWithPath:deviceSetPath error:&innerError];
  if (!deviceSet) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create underlying device set for configuration %@", configuration]
      causedBy:innerError]
      fail:error];
  }
  return deviceSet;
}

#pragma mark Private

+ (NSString *)fullyQualifiedDeviceSetPath:(NSString *)deviceSetPath error:(NSError **)error
{
  NSParameterAssert(deviceSetPath);

  NSError *innerError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create custom SimDeviceSet directory at %@", deviceSetPath]
      causedBy:innerError]
      fail:error];
  }

  // -[NSString stringByResolvingSymlinksInPath] doesn't resolve /var to /private/var.
  // This is important for -[SimServiceContext deviceSetWithPath:error], which internally caches based on a fully resolved path.
  char pathBuffer[PATH_MAX + 1];
  char *result = realpath(deviceSetPath.UTF8String, pathBuffer);
  if (!result) {
    return [[FBSimulatorError
      describeFormat:@"Failed to get realpath for %@ '%s'", deviceSetPath, strerror(errno)]
      fail:error];
  }
  return [[NSString alloc] initWithCString:pathBuffer encoding:NSASCIIStringEncoding];
}


@end
