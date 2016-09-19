/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControl+PrincipalClass.h"

#import <objc/runtime.h>

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimServiceContext.h>
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorServiceContext.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorControlFrameworkLoader.h"

@implementation FBSimulatorControl

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader loadPrivateFrameworksOrAbort];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:FBControlCoreGlobalConfiguration.defaultLogger error:error];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSError *innerError = nil;
  SimServiceContext *simServiceContext = nil;
  if (![self serviceContextWithServiceContextOut:&simServiceContext error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  SimDeviceSet *deviceSet = [self createDeviceSetWithConfiguration:configuration serviceContext:simServiceContext error:&innerError];
  if (!deviceSet) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBSimulatorSet *set = [FBSimulatorSet setWithConfiguration:configuration deviceSet:deviceSet logger:logger error:&innerError];
  if (!set) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBSimulatorServiceContext *serviceContext = simServiceContext ? [FBSimulatorServiceContext contextWithServiceContext:simServiceContext] : nil;
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration serviceContext:serviceContext set:set logger:logger];
}

+ (BOOL)serviceContextWithServiceContextOut:(SimServiceContext **)serviceContextOut error:(NSError **)error
{
  Class serviceContextClass = objc_lookUpClass("SimServiceContext");
  if (![serviceContextClass respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)]) {
    return YES;
  }
  NSError *innerError = nil;
  SimServiceContext *serviceContext = [serviceContextClass sharedServiceContextForDeveloperDir:FBControlCoreGlobalConfiguration.developerDirectory error:&innerError];
  if (!serviceContext) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }
  *serviceContextOut = serviceContext;
  return YES;
}

+ (SimDeviceSet *)createDeviceSetWithConfiguration:(FBSimulatorControlConfiguration *)configuration serviceContext:(nullable SimServiceContext *)serviceContext error:(NSError **)error
{
  NSString *deviceSetPath = configuration.deviceSetPath;
  NSError *innerError = nil;
  if (deviceSetPath != nil) {
    if (![NSFileManager.defaultManager createDirectoryAtPath:deviceSetPath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
      return [[[FBSimulatorError describeFormat:@"Failed to create custom SimDeviceSet directory at %@", deviceSetPath] causedBy:innerError] fail:error];
    }
  }

  SimDeviceSet *deviceSet = nil;
  if (serviceContext) {
    deviceSet = deviceSetPath
      ? [serviceContext deviceSetWithPath:configuration.deviceSetPath error:&innerError]
      : [serviceContext defaultDeviceSetWithError:&innerError];
  } else {
    deviceSet = deviceSetPath
      ? [objc_lookUpClass("SimDeviceSet") setForSetPath:configuration.deviceSetPath]
      : [objc_lookUpClass("SimDeviceSet") defaultSet];
  }

  if (!deviceSet) {
    return [[[FBSimulatorError describeFormat:@"Failed to get device set for %@", deviceSetPath] causedBy:innerError] fail:error];
  }
  return deviceSet;
}

- (nullable instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration serviceContext:(nullable FBSimulatorServiceContext *)serviceContext set:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _serviceContext = serviceContext;
  _set = set;
  _pool = [FBSimulatorPool poolWithSet:set logger:logger];

  return self;
}

@end
