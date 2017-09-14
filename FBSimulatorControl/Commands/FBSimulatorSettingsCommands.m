/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSettingsCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBDefaultsModificationStrategy.h"

FBSimulatorApproval const FBSimulatorApprovalAddressBook = @"kTCCServiceAddressBook";
FBSimulatorApproval const FBSimulatorApprovalPhotos = @"kTCCServicePhotos";
FBSimulatorApproval const FBSimulatorApprovalCamera = @"kTCCServiceCamera";

@interface FBSimulatorSettingsCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorSettingsCommands

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

- (BOOL)overridingLocalization:(FBLocalizationOverride *)localizationOverride error:(NSError **)error
{
  if (!localizationOverride) {
    return YES;
  }

  return [[FBLocalizationDefaultsModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideLocalization:localizationOverride error:error];
}

- (BOOL)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs error:(NSError **)error
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    approveLocationServicesForBundleIDs:bundleIDs error:error];
}

- (BOOL)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [[FBWatchdogOverrideModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideWatchDogTimerForApplications:bundleIDs timeout:timeout error:error];
}

- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSimulatorApproval> *)services
{
  NSString *filePath = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/TCC/TCC.db"];
  if (!filePath) {
    return [[FBSimulatorError
      describeFormat:@"Expected file to exist at path %@ but it was not there", filePath]
      failFuture];
  }
  NSArray<NSString *> *arguments = @[
    filePath,
    [NSString stringWithFormat:@"INSERT or REPLACE INTO access VALUES %@", [FBSimulatorSettingsCommands buildColumnsForBundleIDs:bundleIDs services:services]],
  ];
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sqlite3" arguments:arguments]
    buildFuture]
    onQueue:self.simulator.asyncQueue map:^(FBTask *_) {
      return NSNull.null;
    }];
}

- (BOOL)setupKeyboardWithError:(NSError **)error
{
  return [[FBKeyboardSettingsModificationStrategy
    strategyWithSimulator:self.simulator]
    setupKeyboardWithError:error];
}

#pragma mark Private

+ (NSString *)buildColumnsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBSimulatorApproval> *)services
{
  NSParameterAssert(bundleIDs.count >= 1);
  NSParameterAssert(services.count >= 1);
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (NSString *service in services) {
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 0, 0, 0)", service, bundleID]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

@end
