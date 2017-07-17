/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationDescriptor+Simulator.h"

@implementation FBApplicationDescriptor (Simulator)

#pragma mark Private

+ (nullable instancetype)systemApplicationNamed:(NSString *)appName error:(NSError **)error
{
  return [self applicationWithPath:[self pathForSystemApplicationNamed:appName] installType:FBApplicationInstallTypeSystem error:error];
}

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBApplicationDescriptor *application = [self applicationWithPath:self.pathForSimulatorApplication installType:FBApplicationInstallTypeMac error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

#pragma mark Private

+ (NSString *)pathForSystemApplicationNamed:(NSString *)name
{
  return [[[FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/Applications"]
    stringByAppendingPathComponent:name]
    stringByAppendingPathExtension:@"app"];
}

+ (NSString *)pathForSimulatorApplication
{
  NSString *simulatorBinaryName = FBControlCoreGlobalConfiguration.isXcode7OrGreater ? @"Simulator" : @"iOS Simulator";
  return [[FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

@end
