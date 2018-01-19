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

FBiOSTargetFutureType const FBiOSTargetFutureTypeApproval = @"approve";

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

- (FBFuture<NSNull *> *)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  if (!localizationOverride) {
    return [FBFuture futureWithResult:NSNull.null];
  }

  return [[FBLocalizationDefaultsModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideLocalization:localizationOverride];
}

- (FBFuture<NSNull *> *)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    approveLocationServicesForBundleIDs:bundleIDs];
}

- (FBFuture<NSNull *> *)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout
{
  return [[FBWatchdogOverrideModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideWatchDogTimerForApplications:bundleIDs timeout:timeout];
}

- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services
{
  // We need at least one approval in the array.
  NSParameterAssert(services.count >= 1);

  // Composing different futures due to differences in how these operate.
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  if ([[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys] intersectsSet:services]) {
    [futures addObject:[self modifyTCCDatabaseWithBundleIDs:bundleIDs toServices:services]];
  }
  if ([services containsObject:FBSettingsApprovalServiceLocation]) {
    [futures addObject:[self authorizeLocationSettings:bundleIDs.allObjects]];
  }
  // Don't wrap if there's only one future.
  if (futures.count == 0) {
    return futures.firstObject;
  }
  return [FBFuture futureWithFutures:futures];
}

- (FBFuture<NSNull *> *)updateContacts:(NSString *)databaseDirectory
{
  // Get and confirm the destination directory exists.
  NSString *destinationDirectory = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/AddressBook"];
  if (![NSFileManager.defaultManager fileExistsAtPath:destinationDirectory]) {
    return [[FBSimulatorError
      describeFormat:@"Expected Address Book path to exist at %@ but it was not there", destinationDirectory]
      failFuture];
  }

  // Get the file paths inside this directory
  NSError *error = nil;
  NSArray<NSString *> *addressBookDBPaths = [NSFileManager.defaultManager contentsOfDirectoryAtPath:databaseDirectory error:&error];
  if (!addressBookDBPaths) {
    return [[FBSimulatorError
      describeFormat:@"Failed to get contents of source directory at %@", addressBookDBPaths]
      failFuture];
  }

  // Fail if nothing is provided
  if (!addressBookDBPaths.count) {
    return [[FBSimulatorError
      describe:@"Could not update Address Book DBs when no databases are provided"]
      failFuture];
  }

  // Update the databases.
  NSSet<NSString *> *permissableDatabaseFilepaths = FBSimulatorSettingsCommands.permissableAddressBookDBFilenames;
  for (NSString *sourceFilename in addressBookDBPaths) {
    if (![permissableDatabaseFilepaths containsObject:sourceFilename]) {
      continue;
    }
    NSString *sourceFilePath = [databaseDirectory stringByAppendingPathComponent:sourceFilename];
    NSString *destinationFilePath = [destinationDirectory stringByAppendingPathComponent:sourceFilePath.lastPathComponent];
    if ([NSFileManager.defaultManager fileExistsAtPath:destinationFilePath] && ! [NSFileManager.defaultManager removeItemAtPath:destinationFilePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
    if (![NSFileManager.defaultManager copyItemAtPath:sourceFilePath toPath:destinationFilePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
  }

  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)setupKeyboard
{
  return [[FBKeyboardSettingsModificationStrategy
    strategyWithSimulator:self.simulator]
    setupKeyboard];
}

#pragma mark Private

- (FBFuture<NSNull *> *)modifyTCCDatabaseWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services
{
  NSString *filePath = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/TCC/TCC.db"];
  if (!filePath) {
    return [[FBSimulatorError
      describeFormat:@"Expected file to exist at path %@ but it was not there", filePath]
      failFuture];
  }
  NSArray<NSString *> *arguments = @[
    filePath,
    [NSString stringWithFormat:@"INSERT or REPLACE INTO access VALUES %@", [FBSimulatorSettingsCommands buildRowsForBundleIDs:bundleIDs services:services]],
  ];
  return [FBSimulatorSettingsCommands runSqliteCommandWithArguments:arguments];
}

#pragma mark Private

+ (NSDictionary<FBSettingsApprovalService, NSString *> *)tccDatabaseMapping
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBSettingsApprovalService, NSString *> *mapping;
  dispatch_once(&onceToken, ^{
    mapping = @{
      FBSettingsApprovalServiceContacts: @"kTCCServiceAddressBook",
      FBSettingsApprovalServicePhotos: @"kTCCServicePhotos",
      FBSettingsApprovalServiceCamera: @"kTCCServiceCamera",
      FBSettingsApprovalServiceMicrophone: @"kTCCServiceMicrophone",
    };
  });
  return mapping;
}

+ (NSSet<NSString *> *)permissableAddressBookDBFilenames
{
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *filenames;
  dispatch_once(&onceToken, ^{
    filenames = [NSSet setWithArray:@[
      @"AddressBook.sqlitedb",
      @"AddressBook.sqlitedb-shm",
      @"AddressBook.sqlitedb-wal",
      @"AddressBookImages.sqlitedb",
      @"AddressBookImages.sqlitedb-shm",
      @"AddressBookImages.sqlitedb-wal",
    ]];
  });
  return filenames;
}

+ (NSSet<FBSettingsApprovalService> *)filteredTCCApprovals:(NSSet<FBSettingsApprovalService> *)approvals
{
  NSMutableSet<FBSettingsApprovalService> *filtered = [NSMutableSet setWithSet:approvals];
  [filtered intersectSet:[NSSet setWithArray:self.tccDatabaseMapping.allKeys]];
  return [filtered copy];
}

+ (NSString *)buildRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBSettingsApprovalService> *)services
{
  NSParameterAssert(bundleIDs.count >= 1);
  NSParameterAssert(services.count >= 1);
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBSettingsApprovalService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 0, 0, 0)", serviceName, bundleID]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (FBFuture<NSNull *> *)runSqliteCommandWithArguments:(NSArray<NSString *> *)arguments
{
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sqlite3" arguments:arguments]
    runUntilCompletion]
    mapReplace:NSNull.null];
}

@end

@implementation FBSettingsApproval (FBiOSTargetFuture)

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApproval;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorSettingsCommands> commands = (id<FBSimulatorSettingsCommands>) target;
  if (![target conformsToProtocol:@protocol(FBSimulatorSettingsCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not conform to FBSimulatorSettingsCommands", target]
      failFuture];
  }
  return [[commands
    grantAccess:[NSSet setWithArray:self.bundleIDs] toServices:[NSSet setWithArray:self.services]]
    mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
