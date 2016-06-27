/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerProcessInteractionOperator.h"

#import "FBDeviceOperator.h"

@implementation FBTestManagerProcessInteractionOperator

#pragma mark - Initializers

+ (instancetype)withDeviceOperator:(id<FBDeviceOperator>)deviceOperator
{
  return [[FBTestManagerProcessInteractionOperator alloc] initWithDeviceOperator:deviceOperator];
}

- (instancetype)initWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceOperator = deviceOperator;

  return self;
}

#pragma mark - FBTestManagerMediatorDelegate

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment error:(NSError **)error
{
  if (![self.deviceOperator isApplicationInstalledWithBundleID:bundleID error:error]) {
    if (![self.deviceOperator installApplicationWithPath:path error:error]) {
      return NO;
    }
  }
  if (![self.deviceOperator launchApplicationWithBundleID:bundleID arguments:arguments environment:environment error:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.deviceOperator killApplicationWithBundleID:bundleID error:error];
}

@end
