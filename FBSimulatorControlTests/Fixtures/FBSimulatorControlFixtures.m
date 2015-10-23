/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlFixtures.h"

#import <FBSImulatorControl/FBProcessLaunchConfiguration.h>

#import <FBSimulatorControl/FBSimulatorApplication.h>

@implementation FBSimulatorControlFixtures

+ (FBSimulatorApplication *)tableSearchApplicationWithError:(NSError **)error;
{
  NSString *path = [[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"];
  return [FBSimulatorApplication applicationWithPath:path error:error];
}

+ (FBApplicationLaunchConfiguration *)tableSearchAppLaunch
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:[self tableSearchApplicationWithError:nil]
    arguments:@[]
    environment:@{}];
}

+ (NSString *)photo0Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"photo0" ofType:@"png"];
}

+ (NSString *)photo1Path
{
  return [[NSBundle bundleForClass:self] pathForResource:@"photo1" ofType:@"png"];
}

@end
