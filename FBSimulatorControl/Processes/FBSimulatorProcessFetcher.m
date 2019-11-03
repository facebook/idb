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

NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID = @"FBSIMULATORCONTROL_SIM_UDID";
NSString *const FBSimulatorControlSimulatorLaunchEnvironmentDeviceSetPath = @"FBSIMULATORCONTROL_SIM_SET_PATH";

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

- (NSArray<FBProcessInfo *> *)simulatorApplicationProcesses
{
  NSArray<NSRunningApplication *> *runningApplications = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.iphonesimulator"];
  return [self.processFetcher processInfoForRunningApplications:runningApplications];
}

- (NSDictionary<NSString *, FBProcessInfo *> *)simulatorApplicationProcessesByUDIDs:(NSArray<NSString *> *)udids unclaimed:(NSArray<FBProcessInfo *> *_Nullable * _Nullable)unclaimedOut
{
  NSMutableDictionary<NSString *, FBProcessInfo *> *dictionary = [NSMutableDictionary dictionary];
  NSMutableArray<FBProcessInfo *> *unclaimed = [NSMutableArray array];
  NSSet<NSString *> *fetchSet = [NSSet setWithArray:udids];

  for (FBProcessInfo *process in self.simulatorApplicationProcesses) {
    NSString *udid = [FBSimulatorProcessFetcher udidForSimulatorApplicationProcess:process];
    if (!udid) {
      [unclaimed addObject:process];
      continue;
    }
    if ([fetchSet containsObject:udid]) {
      dictionary[udid] = process;
    }
  }
  if (unclaimedOut) {
    *unclaimedOut = [unclaimed copy];
  }

  return [dictionary copy];
}

- (NSDictionary<id, FBProcessInfo *> *)simulatorApplicationProcessesByDeviceSetPath
{
  NSMutableDictionary<id, FBProcessInfo *> *dictionary = [NSMutableDictionary dictionary];
  for (FBProcessInfo *processInfo in self.simulatorApplicationProcesses) {
    id deviceSetPath = [FBSimulatorProcessFetcher deviceSetPathForApplicationProcess:processInfo] ?: NSNull.null;
    dictionary[deviceSetPath] = processInfo;
  }
  return [dictionary copy];
}

- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice
{
  return [self simulatorApplicationProcessesByUDIDs:@[simDevice.UDID.UUIDString] unclaimed:nil][simDevice.UDID.UUIDString];
}

- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilExists:^{
    return [self simulatorApplicationProcessForSimDevice:simDevice];
  }];
}

#pragma mark The Simulator's launchd_sim

- (NSArray<FBProcessInfo *> *)launchdProcesses
{
  return [self.processFetcher processesWithProcessName:@"launchd_sim"];
}

- (NSDictionary<NSString *, FBProcessInfo *> *)launchdProcessesByUDIDs:(NSArray<NSString *> *)udids
{
  NSDictionary<NSString *, NSString *> *serviceNameToUDID = [FBSimulatorProcessFetcher launchdSimServiceNamesToUDIDs:udids];
  NSDictionary<NSString *, NSDictionary<NSString *, id> *> *jobs = [FBServiceManagement jobInformationForUserServicesNamed:serviceNameToUDID.allKeys];

  NSMutableDictionary<NSString *, FBProcessInfo *> *processes = [NSMutableDictionary dictionary];
  for (NSString *serviceName in serviceNameToUDID.allKeys) {
    NSString *udid = serviceNameToUDID[serviceName];
    NSDictionary<NSString *, id> *job = jobs[serviceName];
    if (!job) {
      continue;
    }
    FBProcessInfo *process = [self.processFetcher processInfoForJobDictionary:job];
    if (!process) {
      continue;
    }
    processes[udid] = process;
  }
  return [processes copy];
}

- (NSDictionary<FBProcessInfo *, NSString *> *)launchdProcessesToContainingDeviceSet
{
  NSMutableDictionary<FBProcessInfo *, NSString *> *dictionary = [NSMutableDictionary dictionary];

  for (FBProcessInfo *process in self.launchdProcesses) {
    NSString *deviceSetPath = [FBSimulatorProcessFetcher deviceSetPathForLaunchdSim:process];
    if (!deviceSetPath) {
      continue;
    }
    dictionary[process] = deviceSetPath;
  }
  return [dictionary copy];
}

- (FBProcessInfo *)launchdProcessForSimDevice:(SimDevice *)simDevice
{
  NSDictionary<NSString *, id> *jobInfo = [FBServiceManagement jobInformationForUserServiceNamed:simDevice.launchdJobName];
  if (!jobInfo) {
    return nil;
  }
  return [self.processFetcher processInfoForJobDictionary:jobInfo];
}

#pragma mark CoreSimulatorService

- (NSArray<FBProcessInfo *> *)coreSimulatorServiceProcesses
{
  return [self.processFetcher processesWithLaunchPathSubstring:@"Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"];
}

#pragma mark Predicates

+ (NSPredicate *)simulatorProcessesWithCorrectLaunchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    return [process.launchPath isEqualToString:FBBundleDescriptor.xcodeSimulator.binary.path];
  }];
}

+ (NSPredicate *)simulatorsProcessesLaunchedUnderConfiguration:(FBSimulatorControlConfiguration *)configuration
{
  NSString *deviceSetPath = configuration.deviceSetPath;
  NSPredicate *argumentsPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    NSSet *arguments = [NSSet setWithArray:process.arguments];
    return [arguments containsObject:deviceSetPath];
  }];

  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    self.simulatorProcessesWithCorrectLaunchPath,
    argumentsPredicate,
  ]];
}

+ (NSPredicate *)simulatorApplicationProcessesLaunchedBySimulatorControl
{
  // All Simulators launched by FBSimulatorControl have a magic string in their environment.
  // This is the safest way to know about other processes launched by FBSimulatorControl
  // since other processes could have launched with UDID arguments.
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *process, NSDictionary *_) {
    NSSet *argumentSet = [NSSet setWithArray:process.environment.allKeys];
    return [argumentSet containsObject:FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
  }];
}

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

+ (nullable NSString *)udidForSimulatorApplicationProcess:(FBProcessInfo *)process
{
  return process.environment[FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID];
}

+ (nullable NSString *)deviceSetPathForApplicationProcess:(FBProcessInfo *)process
{
  return process.environment[FBSimulatorControlSimulatorLaunchEnvironmentDeviceSetPath];
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
