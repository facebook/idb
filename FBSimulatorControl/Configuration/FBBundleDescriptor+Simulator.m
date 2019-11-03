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

+ (nullable instancetype)systemApplicationNamed:(NSString *)appName simulator:(FBSimulator *)simulator error:(NSError **)error
{
  return [self bundleFromPath:[self pathForSystemApplicationNamed:appName simulator:simulator] error:error];
}

+ (instancetype)xcodeSimulator;
{
  NSError *error = nil;
  FBBundleDescriptor *application = [self bundleFromPath:self.pathForSimulatorApplication error:&error];
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
  NSString *simulatorBinaryName =  @"Simulator";
  return [[FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

@end
