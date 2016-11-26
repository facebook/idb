//
//  FBXCTestRunTarget.m
//  FBSimulatorControl
//
//  Created by Johannes Plunien on 26/11/2016.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import "FBXCTestRunTarget.h"

@implementation FBXCTestRunTarget

- (instancetype)initWithName:(NSString *)testTargetName testLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration applications:(NSArray<FBApplicationDescriptor *> *)applications
{
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
