/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBundleDescriptor+Simulator.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator+Private.h"

@implementation FBBundleDescriptor (Simulator)

#pragma mark Private

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBBundleDescriptor *application = [self bundleFromPath:self.pathForSimulatorApplication error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

#pragma mark Private

+ (NSString *)pathForSimulatorApplication
{
  NSString *simulatorBinaryName =  @"Simulator";
  return [[FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

@end
