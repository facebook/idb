/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  NSError *innerError = nil;
  FBSimulatorServiceContext *serviceContext = [FBSimulatorServiceContext sharedServiceContextWithLogger:configuration.logger];
  SimDeviceSet *deviceSet = [serviceContext createDeviceSetWithConfiguration:configuration error:&innerError];
  if (!deviceSet) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBSimulatorSet *set = [FBSimulatorSet setWithConfiguration:configuration deviceSet:deviceSet delegate:nil logger:[configuration.logger withName:@"simulator_set"] reporter:configuration.reporter error:&innerError];
  if (!set) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  return [[FBSimulatorControl alloc] initWithConfiguration:configuration serviceContext:serviceContext set:set logger:configuration.logger];
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

  return self;
}

@end
