/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorProcessFetcher.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBBundleDescriptor+Simulator.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"

@implementation FBSimulatorProcessFetcher

+ (instancetype)fetcherWithProcessFetcher:(FBProcessFetcher *)processFetcher
{
  return [[self alloc] initWithProcessFetcher:processFetcher];
}

- (instancetype)initWithProcessFetcher:(FBProcessFetcher *)processFetcher
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processFetcher = processFetcher;

  return self;
}

#pragma mark CoreSimulatorService

- (NSArray<FBProcessInfo *> *)coreSimulatorServiceProcesses
{
  return [self.processFetcher processesWithLaunchPathSubstring:@"Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"];
}

#pragma mark Predicates

+ (NSPredicate *)coreSimulatorProcessesForCurrentXcode
{
  return [FBProcessFetcher processesWithLaunchPath:FBXcodeConfiguration.developerDirectory];
}

#pragma mark Private

+ (nullable NSString *)udidForLaunchdSim:(FBProcessInfo *)process
{
  if ([process.launchPath rangeOfString:@"launchd_sim"].location == NSNotFound) {
    return nil;
  }
  NSString *udidContainingString = process.environment[@"XPC_SIMULATOR_LAUNCHD_NAME"];
  NSCharacterSet *characterSet = self.launchdSimEnvironmentVariableUDIDSplitCharacterSet;
  NSMutableSet<NSString *> *components = [NSMutableSet setWithArray:[udidContainingString componentsSeparatedByCharactersInSet:characterSet]];
  [components minusSet:self.launchdSimEnvironmentSubtractableComponents];
  if (components.count != 1) {
    return nil;
  }
  return [components anyObject];
}

+ (nullable NSString *)deviceSetPathForLaunchdSim:(FBProcessInfo *)process
{
  NSString *udid = [self udidForLaunchdSim:process];
  if (!udid) {
    return nil;
  }
  if (process.arguments.count < 2) {
    return nil;
  }
  NSString *bootstrapPath = process.arguments[1];
  if (![bootstrapPath.lastPathComponent isEqualToString:@"launchd_bootstrap.plist"]) {
    return nil;
  }
  NSString *deviceSetPath = [[[[[bootstrapPath
    stringByDeletingLastPathComponent] //launchd_bootstrap.plist
    stringByDeletingLastPathComponent] // run
    stringByDeletingLastPathComponent] // var
    stringByDeletingLastPathComponent] // data
    stringByDeletingLastPathComponent]; // Simulator UDID

  NSString *simulatorRootPath = [deviceSetPath stringByAppendingString:udid];
  if ([NSFileManager.defaultManager fileExistsAtPath:simulatorRootPath]) {
    return nil;
  }
  return deviceSetPath;
}

+ (NSCharacterSet *)launchdSimEnvironmentVariableUDIDSplitCharacterSet
{
  static dispatch_once_t onceToken;
  static NSCharacterSet *characterSet;
  dispatch_once(&onceToken, ^{
    characterSet = [NSCharacterSet characterSetWithCharactersInString:@"."];
  });
  return characterSet;
}

+ (NSDictionary<NSString *, NSString *> *)launchdSimServiceNamesToUDIDs:(NSArray<NSString *> *)udids
{
  NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];
  for (NSString *udid in udids) {
    NSString *serviceName = [self xcode8LaunchdSimServiceNameForUDID:udid];
    dictionary[serviceName] = udid;
    serviceName = [self xcode9LaunchdSimServiceNameForUDID:udid];
    dictionary[serviceName] = udid;
  }
  return [dictionary copy];
}

+ (NSString *)xcode8LaunchdSimServiceNameForUDID:(NSString *)udid
{
  return [NSString stringWithFormat:@"com.apple.CoreSimulator.SimDevice.%@.launchd_sim", udid];
}

+ (NSString *)xcode9LaunchdSimServiceNameForUDID:(NSString *)udid
{
  return [NSString stringWithFormat:@"com.apple.CoreSimulator.SimDevice.%@", udid];
}

+ (NSSet<NSString *> *)launchdSimEnvironmentSubtractableComponents
{
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *components;
  dispatch_once(&onceToken, ^{
    components = [NSSet setWithArray:@[
      @"com",
      @"apple",
      @"CoreSimulator",
      @"SimDevice",
      @"launchd_sim",
    ]];
  });
  return components;
}

@end
