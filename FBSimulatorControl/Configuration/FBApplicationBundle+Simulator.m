/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBApplicationBundle+Simulator.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator+Private.h"

@implementation FBApplicationBundle (Simulator)

#pragma mark Private

+ (nullable instancetype)systemApplicationNamed:(NSString *)appName simulator:(FBSimulator *)simulator error:(NSError **)error
{
  return [self applicationWithPath:[self pathForSystemApplicationNamed:appName simulator:simulator] error:error];
}

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBApplicationBundle *application = [self applicationWithPath:self.pathForSimulatorApplication error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

#pragma mark Private

+ (NSString *)pathForSystemApplicationNamed:(NSString *)name simulator:(FBSimulator *)simulator
{
  NSString *runtimeRoot = simulator.device.runtime.root;
  return [[[runtimeRoot
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:name]
    stringByAppendingPathExtension:@"app"];
}

+ (NSString *)pathForSimulatorApplication
{
  NSString *simulatorBinaryName = FBXcodeConfiguration.isXcode7OrGreater ? @"Simulator" : @"iOS Simulator";
  return [[FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

@end
