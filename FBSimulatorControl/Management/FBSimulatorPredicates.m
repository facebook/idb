/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorPredicates.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorControlConfiguration.h"

@implementation FBSimulatorPredicates

+ (NSPredicate *)launched
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *simulator, NSDictionary *_) {
    return simulator.launchdProcess.processIdentifier > 1;
  }];
}

#pragma mark Configurations

+ (NSPredicate *)configuration:(FBSimulatorConfiguration *)configuration
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBSimulator *candidate, NSDictionary *_) {
    if (![candidate.configuration.device isEqual:configuration.device]) {
      return NO;
    }
    if (![candidate.configuration.os isEqual:configuration.os]) {
      return NO;
    }
    return YES;
  }];
}

+ (NSPredicate *)configurations:(NSArray<FBSimulatorConfiguration *> *)configurations
{
  NSMutableArray<NSPredicate *> *subpredicates = [NSMutableArray array];
  for (FBSimulatorConfiguration *configuration in configurations) {
    [subpredicates addObject:[self configuration:configuration]];
  }
  return [NSCompoundPredicate orPredicateWithSubpredicates:subpredicates];
}

@end
