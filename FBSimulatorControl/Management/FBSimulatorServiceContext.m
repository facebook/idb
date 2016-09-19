/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorServiceContext.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>
#import <CoreSimulator/SimRuntime.h>
#import <CoreSimulator/SimServiceContext.h>

@implementation FBSimulatorServiceContext

+ (instancetype)contextWithServiceContext:(SimServiceContext *)serviceContext
{
  return [[self alloc] initWithServiceContext:serviceContext];
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

- (NSArray<NSString *> *)pathsOfAllDeviceSets
{
  NSMutableArray<NSString *> *deviceSetPaths = [NSMutableArray array];
  for (SimDeviceSet *deviceSet in self.serviceContext.allDeviceSets) {
    [deviceSetPaths addObject:deviceSet.setPath];
  }
  return [deviceSetPaths copy];
}

@end
