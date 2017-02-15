/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRunTarget.h"

@implementation FBXCTestRunTarget

- (instancetype)initWithName:(NSString *)testTargetName testLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration applications:(NSArray<FBApplicationDescriptor *> *)applications
{
  NSParameterAssert(testTargetName);
  NSParameterAssert(testLaunchConfiguration);
  NSParameterAssert(applications);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = [testTargetName copy];
  _testLaunchConfiguration = testLaunchConfiguration;
  _applications = [applications copy];

  return self;
}

+ (instancetype)withName:(NSString *)testTargetName testLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration applications:(NSArray<FBApplicationDescriptor *> *)applications
{
  return [[self alloc] initWithName:testTargetName testLaunchConfiguration:testLaunchConfiguration applications:applications];
}

@end
