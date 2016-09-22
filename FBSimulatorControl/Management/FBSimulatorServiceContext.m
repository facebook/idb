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
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>
#import <CoreSimulator/SimServiceContext.h>

#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorServiceContext ()

@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

- (instancetype)initWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher;

- (SimDeviceSet *)createUnderlyingDeviceSet:(NSString *)deviceSetPath error:(NSError **)error;

@end

@interface FBSimulatorServiceContext_ContextBacked : FBSimulatorServiceContext

@property (nonatomic, strong, readonly) SimServiceContext *serviceContext;

- (instancetype)initWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher serviceContext:(SimServiceContext *)serviceContext;

@end

@interface FBSimulatorServiceContext_Emulated : FBSimulatorServiceContext

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
  FBSimulatorProcessFetcher *processFetcher = [FBSimulatorProcessFetcher fetcherWithProcessFetcher:[FBProcessFetcher new]];

  Class serviceContextClass = objc_lookUpClass("SimServiceContext");
  if ([serviceContextClass respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)]) {
    NSError *innerError = nil;
    SimServiceContext *serviceContext = [serviceContextClass sharedServiceContextForDeveloperDir:FBControlCoreGlobalConfiguration.developerDirectory error:&innerError];
    NSAssert(serviceContext, @"Could not create a service context with error %@", innerError);
    return [[FBSimulatorServiceContext_ContextBacked alloc] initWithProcessFetcher:processFetcher serviceContext:serviceContext];
  }
  return [[FBSimulatorServiceContext_Emulated alloc] initWithProcessFetcher:processFetcher];
}

- (instancetype)initWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processFetcher = processFetcher;

  return self;
}

#pragma mark Public

- (NSArray<NSString *> *)pathsOfAllDeviceSets
{
  return [[self.processFetcher launchdProcessesToContainingDeviceSet] allValues];
}
- (NSArray<SimRuntime *> *)supportedRuntimes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSArray<SimDeviceType *> *)supportedDeviceTypes
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;

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
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (BOOL)createDeviceSetDirectoryIfNeeded:(NSString *)deviceSetPath error:(NSError **)error
{
  NSError *innerError = nil;
  if (deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to create custom SimDeviceSet directory at %@", deviceSetPath]
        causedBy:innerError]
        failBool:error];
    }
  }
  return YES;
}

@end

@implementation FBSimulatorServiceContext_Emulated

- (NSArray<SimRuntime *> *)supportedRuntimes
{
  return [objc_lookUpClass("SimRuntime") supportedRuntimes];
}

- (NSArray<SimDeviceType *> *)supportedDeviceTypes
{
  return [objc_lookUpClass("SimDeviceType") supportedDeviceTypes];
}

- (SimDeviceSet *)createUnderlyingDeviceSet:(NSString *)deviceSetPath error:(NSError **)error
{
  return deviceSetPath
    ? [objc_lookUpClass("SimDeviceSet") setForSetPath:deviceSetPath]
    : [objc_lookUpClass("SimDeviceSet") defaultSet];
}

@end

@implementation FBSimulatorServiceContext_ContextBacked

- (instancetype)initWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher serviceContext:(SimServiceContext *)serviceContext
{
  self = [super initWithProcessFetcher:processFetcher];
  if (!self) {
    return nil;
  }

  _serviceContext = serviceContext;

  return self;
}

- (NSArray<NSString *> *)pathsOfAllDeviceSets
{
  NSMutableSet<NSString *> *deviceSetPaths = [NSMutableSet setWithArray:[super pathsOfAllDeviceSets]];
  for (SimDeviceSet *deviceSet in self.serviceContext.allDeviceSets) {
    [deviceSetPaths addObject:deviceSet.setPath];
  }
  return [deviceSetPaths allObjects];
}

- (NSArray<SimRuntime *> *)supportedRuntimes
{
  return [self.serviceContext supportedRuntimes];
}

- (NSArray<SimDeviceType *> *)supportedDeviceTypes
{
  return [self.serviceContext supportedDeviceTypes];
}

- (SimDeviceSet *)createUnderlyingDeviceSet:(NSString *)deviceSetPath error:(NSError **)error
{
  return deviceSetPath
    ? [self.serviceContext deviceSetWithPath:deviceSetPath error:error]
    : [self.serviceContext defaultDeviceSetWithError:error];
}

@end
