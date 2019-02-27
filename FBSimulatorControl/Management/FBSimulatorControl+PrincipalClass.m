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

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimServiceContext.h>
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorConfiguration.h"
#import "FBSimulatorServiceContext.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorControlFrameworkLoader.h"

@implementation FBSimulatorControl

#pragma mark Initializers

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error
{
  return [self withConfiguration:configuration logger:FBControlCoreGlobalConfiguration.defaultLogger error:error];
}

+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSError *innerError = nil;
  FBSimulatorServiceContext *serviceContext = [FBSimulatorServiceContext sharedServiceContext];
  SimDeviceSet *deviceSet = [serviceContext createDeviceSetWithConfiguration:configuration error:&innerError];
  if (!deviceSet) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBSimulatorSet *set = [FBSimulatorSet setWithConfiguration:configuration deviceSet:deviceSet logger:[logger withName:@"simulator_set"] error:&innerError delegate:nil];
  if (!set) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration serviceContext:serviceContext set:set logger:logger];
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
