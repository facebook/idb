/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorSettingsCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAppleSimctlCommandExecutor.h"
#import "FBDefaultsModificationStrategy.h"
#import "FBSimulator.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"


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

#pragma mark Public

- (FBFuture<NSNull *> *)setSetting:(FBSimulatorSetting)setting enabled:(BOOL)enabled
{
  switch (setting) {
    case FBSimulatorSettingHardwareKeyboard:
      return [self setHardwareKeyboardEnabled:enabled];
    case FBSimulatorSettingSlowAnimations:
      return [self setSlowAnimationsEnabled:enabled];
    default:
      return [[FBSimulatorError describeFormat:@"Unknown simulator setting: %lu", (unsigned long)setting] failFuture];
  }
}

- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled
{
  if ([self.simulator.device respondsToSelector:(@selector(setHardwareKeyboardEnabled:keyboardType:error:))]) {
    return [FBFuture onQueue:self.simulator.workQueue resolve:^ FBFuture<NSNull *> * () {
      NSError *error = nil;
      [self.simulator.device setHardwareKeyboardEnabled:enabled keyboardType:0 error:&error];

      return FBFuture.empty;
    }];
  }

  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (FBSimulatorBridge *bridge) {
      return [bridge setHardwareKeyboardEnabled:enabled];
    }];
}

- (FBFuture<NSNull *> *)setPreference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain;
{
  return [[FBPreferenceModificationStrategy
    strategyWithSimulator:self.simulator]
          setPreference:name value:value type: type domain:domain];
}

- (FBFuture<NSString *> *)getCurrentPreference:(NSString *)name domain:(nullable NSString *)domain;
{
  return [[FBPreferenceModificationStrategy
    strategyWithSimulator:self.simulator]
    getCurrentPreference:name domain:domain];
}

- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBTargetSettingsService> *)services
{
  // We need at least one approval in the input
  if (services.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve any services for %@ since no services were provided", bundleIDs]
      failFuture];
  }
  // We also need at least one bundle id in the input.
  if (bundleIDs.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve %@ since no bundle ids were provided", services]
      failFuture];
  }

  // Composing different futures due to differences in how these operate.
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  NSMutableSet<NSString *> *toApprove = [NSMutableSet setWithSet:services];
  FBOSVersion *iosVer = [self.simulator osVersion];
  NSDictionary<FBTargetSettingsService, NSString *> *coreSimulatorSettingMapping;

  if (iosVer.version.majorVersion >= 13) {
    coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPostIos13;
  } else {
    coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPreIos13;
  }

  // Go through each of the internal APIs, removing them from the pending set as we go.
  if ([self.simulator.device respondsToSelector:@selector(setPrivacyAccessForService:bundleID:granted:error:)]) {
    NSMutableSet<NSString *> *simDeviceServices = [toApprove mutableCopy];
    [simDeviceServices intersectSet:[NSSet setWithArray:coreSimulatorSettingMapping.allKeys]];
    // Only approve these services, where they are serviced by the CoreSimulator API
    if (simDeviceServices.count > 0) {
      NSMutableSet<NSString *> *internalServices = [NSMutableSet set];
      for (NSString *service in simDeviceServices) {
        NSString *internalService = coreSimulatorSettingMapping[service];
        [internalServices addObject:internalService];
      }
      [toApprove minusSet:simDeviceServices];
      [futures addObject:[self coreSimulatorApproveWithBundleIDs:bundleIDs toServices:internalServices]];
    }
  }
  if (toApprove.count > 0 && [[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys] intersectsSet:toApprove]) {
    NSMutableSet<NSString *> *tccServices = [toApprove mutableCopy];
    [tccServices intersectSet:[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys]];
    [toApprove minusSet:tccServices];
    [futures addObject:[self modifyTCCDatabaseWithBundleIDs:bundleIDs toServices:tccServices grantAccess:YES]];
  }
  if (toApprove.count > 0 && [toApprove containsObject:FBTargetSettingsServiceLocation]) {
    [futures addObject:[self authorizeLocationSettings:bundleIDs.allObjects]];
    [toApprove removeObject:FBTargetSettingsServiceLocation];
  }
  if (toApprove.count > 0 && [toApprove containsObject:FBTargetSettingsServiceNotification]) {
    [futures addObject:[self updateNotificationService:bundleIDs.allObjects approve:YES]];
    [toApprove removeObject:FBTargetSettingsServiceNotification];
  }

  // Error out if there's nothing we can do to handle a specific approval.
  if (toApprove.count > 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve %@ since there is no handling of it", [FBCollectionInformation oneLineDescriptionFromArray:toApprove.allObjects]]
      failFuture];
  }
  // Nothing to do with zero futures.
  if (futures.count == 0) {
    return FBFuture.empty;
  }
  // Don't wrap if there's only one future.
  if (futures.count == 1) {
    return futures.firstObject;
  }
  return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)revokeAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBTargetSettingsService> *)services
{
  // We need at least one revoke in the input
  if (services.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot revoke any services for %@ since no services were provided", bundleIDs]
      failFuture];
  }
  // We also need at least one bundle id in the input.
  if (bundleIDs.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot revoke %@ since no bundle ids were provided", services]
      failFuture];
  }

  // Composing different futures due to differences in how these operate.
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  NSMutableSet<NSString *> *toRevoke = [NSMutableSet setWithSet:services];
  FBOSVersion *iosVer = [self.simulator osVersion];
  NSDictionary<FBTargetSettingsService, NSString *> *coreSimulatorSettingMapping;

  if (iosVer.version.majorVersion >= 13) {
    coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPostIos13;
  } else {
    coreSimulatorSettingMapping = FBSimulatorSettingsCommands.coreSimulatorSettingMappingPreIos13;
  }

  // Go through each of the internal APIs, removing them from the pending set as we go.
  if ([self.simulator.device respondsToSelector:@selector(setPrivacyAccessForService:bundleID:granted:error:)]) {
    NSMutableSet<NSString *> *simDeviceServices = [toRevoke mutableCopy];
    [simDeviceServices intersectSet:[NSSet setWithArray:coreSimulatorSettingMapping.allKeys]];
    // Only revoke these services, where they are serviced by the CoreSimulator API
    if (simDeviceServices.count > 0) {
      NSMutableSet<NSString *> *internalServices = [NSMutableSet set];
      for (NSString *service in simDeviceServices) {
        NSString *internalService = coreSimulatorSettingMapping[service];
        [internalServices addObject:internalService];
      }
      [toRevoke minusSet:simDeviceServices];
      [futures addObject:[self coreSimulatorRevokeWithBundleIDs:bundleIDs toServices:internalServices]];
    }
  }
  if (toRevoke.count > 0 && [[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys] intersectsSet:toRevoke]) {
    NSMutableSet<NSString *> *tccServices = [toRevoke mutableCopy];
    [tccServices intersectSet:[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys]];
    [toRevoke minusSet:tccServices];
    [futures addObject:[self modifyTCCDatabaseWithBundleIDs:bundleIDs toServices:tccServices grantAccess:NO]];
  }
  if (toRevoke.count > 0 && [toRevoke containsObject:FBTargetSettingsServiceLocation]) {
    [futures addObject:[self revokeLocationSettings:bundleIDs.allObjects]];
    [toRevoke removeObject:FBTargetSettingsServiceLocation];
  }
  if (toRevoke.count > 0 && [toRevoke containsObject:FBTargetSettingsServiceNotification]) {
    [futures addObject:[self updateNotificationService:bundleIDs.allObjects approve:NO]];
    [toRevoke removeObject:FBTargetSettingsServiceNotification];
  }

  // Error out if there's nothing we can do to handle a specific approval.
  if (toRevoke.count > 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve %@ since there is no handling of it", [FBCollectionInformation oneLineDescriptionFromArray:toRevoke.allObjects]]
      failFuture];
  }
  // Nothing to do with zero futures.
  if (futures.count == 0) {
    return FBFuture.empty;
  }
  // Don't wrap if there's only one future.
  if (futures.count == 1) {
    return futures.firstObject;
  }
  return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toDeeplink:(NSString *)scheme
{
  if ([scheme length] == 0) {
    return [[FBSimulatorError
      describe:@"Empty scheme provided to url approve"]
      failFuture];
  }
  if ([bundleIDs count] == 0) {
    return [[FBSimulatorError
      describe:@"Empty bundleID set provided to url approve"]
      failFuture];
  }

  NSString *preferencesDirectory = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/Preferences"];
  NSString *schemeApprovalPlistPath = [preferencesDirectory stringByAppendingPathComponent:@"com.apple.launchservices.schemeapproval.plist"];

  //Read the existing file if it exists. Otherwise create a new dictionary
  NSMutableDictionary<NSString *, NSString *> *schemeApprovalProperties = [NSMutableDictionary new];
  if ([NSFileManager.defaultManager fileExistsAtPath:schemeApprovalPlistPath]) {
    schemeApprovalProperties = [[NSDictionary dictionaryWithContentsOfFile:schemeApprovalPlistPath] mutableCopy];
    if (schemeApprovalProperties == nil) {
      return [[FBSimulatorError
        describeFormat:@"Failed to read the file at %@", schemeApprovalPlistPath]
        failFuture];
    }
  }

  NSString *urlKey = [FBSimulatorSettingsCommands magicDeeplinkKeyForScheme:scheme];
  for (NSString *bundleID in bundleIDs) {
    schemeApprovalProperties[urlKey] = bundleID;
  }

  //Write our plist back
  NSError *error = nil;
  BOOL success = [NSFileManager.defaultManager
    createDirectoryAtPath:preferencesDirectory
    withIntermediateDirectories:YES
    attributes:nil
    error:&error];
  if (!success) {
    return [[FBSimulatorError
      describe:@"Failed to create folders for scheme approval plist"]
      failFuture];
  }
  success = [schemeApprovalProperties writeToFile:schemeApprovalPlistPath atomically:YES];
  if (!success) {
    return [[FBSimulatorError
      describe:@"Failed to write scheme approval plist"]
      failFuture];
  }
  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)revokeAccess:(NSSet<NSString *> *)bundleIDs toDeeplink:(NSString *)scheme
{
  if ([scheme length] == 0) {
    return [[FBSimulatorError
      describe:@"Empty scheme provided to url revoke"]
      failFuture];
  }
  if ([bundleIDs count] == 0) {
    return [[FBSimulatorError
      describe:@"Empty bundleID set provided to url revoke"]
      failFuture];
  }

  NSString *preferencesDirectory = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/Preferences"];
  NSString *schemeApprovalPlistPath = [preferencesDirectory stringByAppendingPathComponent:@"com.apple.launchservices.schemeapproval.plist"];

  // Read the existing file if it exists
  NSMutableDictionary<NSString *, NSString *> *schemeApprovalProperties = [NSMutableDictionary new];
  if ([NSFileManager.defaultManager fileExistsAtPath:schemeApprovalPlistPath]) {
    schemeApprovalProperties = [[NSDictionary dictionaryWithContentsOfFile:schemeApprovalPlistPath] mutableCopy];
    if (schemeApprovalProperties == nil) {
      return [[FBSimulatorError
        describeFormat:@"Failed to read the file at %@", schemeApprovalPlistPath]
        failFuture];
    }
  } else {
    // If the file of scheme approvals doesn't exist, then there's nothing we need to revoke
    return FBFuture.empty;
  }

  NSString *urlKey = [FBSimulatorSettingsCommands magicDeeplinkKeyForScheme:scheme];
  [schemeApprovalProperties removeObjectForKey:urlKey];

  //Write the plist back
  BOOL success = [schemeApprovalProperties writeToFile:schemeApprovalPlistPath atomically:YES];
  if (!success) {
    return [[FBSimulatorError
      describe:@"Failed to write scheme approval plist"]
      failFuture];
  }
  return FBFuture.empty;
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

  // Obtain the relevant file paths
  NSError *error = nil;
  NSArray<NSString *> *sourceFilePaths = [FBSimulatorSettingsCommands contactsDatabaseFilePathsFromContainingDirectory:databaseDirectory error:&error];
  if (!sourceFilePaths) {
    return [FBFuture futureWithError:error];
  }


  // Perform the copies
  for (NSString *sourceFilePath in sourceFilePaths) {
    NSString *destinationFilePath = [destinationDirectory stringByAppendingPathComponent:sourceFilePath.lastPathComponent];
    if ([NSFileManager.defaultManager fileExistsAtPath:destinationFilePath] && ! [NSFileManager.defaultManager removeItemAtPath:destinationFilePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
    if (![NSFileManager.defaultManager copyItemAtPath:sourceFilePath toPath:destinationFilePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
  }

  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)clearContacts
{
  return [self runSimulatorFrameworkBridgeWithService:@"contacts" action:@"clear"];
}

- (FBFuture<NSNull *> *)clearPhotos
{
  return [self runSimulatorFrameworkBridgeWithService:@"photos" action:@"clear"];
}

static NSString *const SlowAnimationsNotification = @"com.apple.UIKit.SimulatorSlowMotionAnimationState";

- (FBFuture<NSNull *> *)setSlowAnimationsEnabled:(BOOL)enabled
{
  return [self setDarwinNotificationState:enabled name:SlowAnimationsNotification];
}

#pragma mark Private

- (FBFuture<NSNull *> *)setDarwinNotificationState:(BOOL)enabled name:(NSString *)name
{
  return [FBFuture onQueue:self.simulator.workQueue resolveValue:^NSNull *(NSError **error) {
    if (![self.simulator.device darwinNotificationSetState:(enabled ? 1 : 0) name:name error:error]) {
      return nil;
    }
    if (![self.simulator.device postDarwinNotification:name error:error]) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)runSimulatorFrameworkBridgeWithService:(NSString *)service action:(NSString *)action
{
  return [self runSimulatorFrameworkBridgeWithService:service action:action arguments:@[]];
}

- (FBFuture<NSNull *> *)runSimulatorFrameworkBridgeWithService:(NSString *)service action:(NSString *)action arguments:(NSArray<NSString *> *)arguments
{
  return [FBFuture onQueue:self.simulator.asyncQueue resolve:^{
    NSString *helperPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"SimulatorFrameworkBridge" ofType:nil];
    if (!helperPath) {
      return [[FBSimulatorError
        describe:@"SimulatorFrameworkBridge binary not found in bundle resources. Ensure FBSimulatorControl was built correctly."]
        failFuture];
    }

    if (![NSFileManager.defaultManager fileExistsAtPath:helperPath]) {
      return [[FBSimulatorError
        describeFormat:@"SimulatorFrameworkBridge binary found in bundle but does not exist at path: %@", helperPath]
        failFuture];
    }

    NSMutableArray<NSString *> *spawnArguments = [NSMutableArray arrayWithObjects:helperPath, service, action, nil];
    [spawnArguments addObjectsFromArray:arguments];

    return [[[self.simulator.simctlExecutor
      taskBuilderWithCommand:@"spawn" arguments:spawnArguments]
      runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
      onQueue:self.simulator.asyncQueue fmap:^(FBSubprocess *task) {
        [self.simulator.logger logFormat:@"SimulatorFrameworkBridge %@ %@ completed successfully", service, action];
        return [FBFuture futureWithResult:NSNull.null];
      }];
  }];
}

- (FBFuture<NSNull *> *)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    approveLocationServicesForBundleIDs:bundleIDs];
}

- (FBFuture<NSNull *> *)revokeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    revokeLocationServicesForBundleIDs:bundleIDs];
}

- (FBFuture<NSNull *> *)updateNotificationService:(NSArray<NSString *> *)bundleIDs approve:(BOOL)approved
{
  if ([bundleIDs count] == 0) {
    return [[FBSimulatorError
      describe:@"Empty bundleID set provided to notifications approve"]
      failFuture];
  }

  NSString *action = approved ? @"approve" : @"revoke";
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    [futures addObject:[self runSimulatorFrameworkBridgeWithService:@"notifications" action:action arguments:@[bundleID]]];
  }
  return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)modifyTCCDatabaseWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBTargetSettingsService> *)services grantAccess:(BOOL)grantAccess
{
  NSString *databasePath = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/TCC/TCC.db"];
  BOOL isDirectory = YES;
  if (![NSFileManager.defaultManager fileExistsAtPath:databasePath isDirectory:&isDirectory]) {
    return [[FBSimulatorError
      describeFormat:@"Expected file to exist at path %@ but it was not there", databasePath]
      failFuture];
  }
  if (isDirectory) {
    return [[FBSimulatorError
      describeFormat:@"Expected file to exist at path %@ but it is a directory", databasePath]
      failFuture];
  }
  if ([NSFileManager.defaultManager isWritableFileAtPath:databasePath] == NO) {
    return [[FBSimulatorError
      describeFormat:@"Database file at path %@ is not writable", databasePath]
      failFuture];
  }

  id<FBControlCoreLogger> logger = [self.simulator.logger withName:@"sqlite_auth"];
  dispatch_queue_t queue = self.simulator.asyncQueue;

  if (grantAccess) {
    return [self
      grantAccessInTCCDatabase:databasePath
      bundleIDs:bundleIDs
      services:services
      queue:queue
      logger:logger];
  } else {
    return [self
      revokeAccessInTCCDatabase:databasePath
      bundleIDs:bundleIDs
      services:services
      queue:queue
      logger:logger];
  }
}

- (FBFuture<NSNull *> *)coreSimulatorApproveWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<NSString *> *)services
{
  for (NSString *bundleID in bundleIDs) {
    for (NSString *internalService in services) {
      NSError *error = nil;
      if (![self.simulator.device setPrivacyAccessForService:internalService bundleID:bundleID granted:YES error:&error]) {
        return [FBFuture futureWithError:error];
      }
    }
  }
  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)coreSimulatorRevokeWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<NSString *> *)services
{
  for (NSString *bundleID in bundleIDs) {
    for (NSString *internalService in services) {
      NSError *error = nil;
      if (![self.simulator.device resetPrivacyAccessForService:internalService bundleID:bundleID error:&error]) {
        return [FBFuture futureWithError:error];
      }
    }
  }
  return FBFuture.empty;
}

+ (NSDictionary<FBTargetSettingsService, NSString *> *)tccDatabaseMapping
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBTargetSettingsService, NSString *> *mapping;
  dispatch_once(&onceToken, ^{
    mapping = @{
      FBTargetSettingsServiceContacts: @"kTCCServiceAddressBook",
      FBTargetSettingsServicePhotos: @"kTCCServicePhotos",
      FBTargetSettingsServiceCamera: @"kTCCServiceCamera",
      FBTargetSettingsServiceMicrophone: @"kTCCServiceMicrophone",
    };
  });
  return mapping;
}

+ (NSDictionary<FBTargetSettingsService, NSString *> *)coreSimulatorSettingMappingPreIos13
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBTargetSettingsService, NSString *> *mapping;
  dispatch_once(&onceToken, ^{
    mapping = @{
      FBTargetSettingsServiceContacts: @"kTCCServiceContactsFull",
      FBTargetSettingsServicePhotos: @"kTCCServicePhotos",
      FBTargetSettingsServiceCamera: @"camera",
      FBTargetSettingsServiceLocation: @"__CoreLocationAlways",
      FBTargetSettingsServiceMicrophone: @"kTCCServiceMicrophone",
    };
  });
  return mapping;
}

+ (NSDictionary<FBTargetSettingsService, NSString *> *)coreSimulatorSettingMappingPostIos13
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBTargetSettingsService, NSString *> *mapping;
  dispatch_once(&onceToken, ^{
    mapping = @{
      FBTargetSettingsServiceLocation: @"__CoreLocationAlways",
    };
  });
  return mapping;
}

+ (NSSet<NSString *> *)permissibleAddressBookDBFilenames
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

+ (NSSet<FBTargetSettingsService> *)filteredTCCApprovals:(NSSet<FBTargetSettingsService> *)approvals
{
  NSMutableSet<FBTargetSettingsService> *filtered = [NSMutableSet setWithSet:approvals];
  [filtered intersectSet:[NSSet setWithArray:self.tccDatabaseMapping.allKeys]];
  return [filtered copy];
}

- (FBFuture<NSNull *> *)grantAccessInTCCDatabase:(NSString *)databasePath bundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[FBSimulatorSettingsCommands
    buildRowsForDatabase:databasePath bundleIDs:bundleIDs services:services queue:queue logger:logger]
    onQueue:self.simulator.workQueue fmap:^(NSString *rows) {
      return [FBSimulatorSettingsCommands
        runSqliteCommandOnDatabase:databasePath
        arguments:@[[NSString stringWithFormat:@"INSERT or REPLACE INTO access VALUES %@", rows]]
        queue:queue
        logger:logger];
    }]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)revokeAccessInTCCDatabase:(NSString *)databasePath bundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray<NSString *> *deletions = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBTargetSettingsService service in [FBSimulatorSettingsCommands filteredTCCApprovals:services]) {
      [deletions addObject:
       [NSString stringWithFormat:@"(service = '%@' AND client = '%@')",
        [FBSimulatorSettingsCommands tccDatabaseMapping][service],
        bundleID]
      ];
    }
  }
  // Nothing to do with no modifications
  if (deletions.count == 0) {
    return FBFuture.empty;
  }
  return [
    [FBSimulatorSettingsCommands
      runSqliteCommandOnDatabase:databasePath
      arguments:@[
        [NSString stringWithFormat:@"DELETE FROM access WHERE %@",
        [deletions componentsJoinedByString:@" OR "]]
      ]
      queue:queue
      logger:logger]
    mapReplace:NSNull.null];
}

+ (FBFuture<NSString *> *)buildRowsForDatabase:(NSString *)databasePath bundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(bundleIDs.count >= 1);
  NSParameterAssert(services.count >= 1);

  return [[self
    runSqliteCommandOnDatabase:databasePath arguments:@[@".schema access"] queue:queue logger:logger]
    onQueue:queue map:^(NSString *result) {
      if ([result containsString:@"last_reminded"]) {
        return [FBSimulatorSettingsCommands postiOS17ApprovalRowsForBundleIDs:bundleIDs services:services];
      } else if ([result containsString:@"auth_value"]) {
        return [FBSimulatorSettingsCommands postiOS15ApprovalRowsForBundleIDs:bundleIDs services:services];
      } else if ([result containsString:@"last_modified"]) {
        return [FBSimulatorSettingsCommands postiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
      } else {
        return [FBSimulatorSettingsCommands preiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
      }
  }];
}

+ (NSString *)preiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services
{
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBTargetSettingsService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 0, 0, 0)", serviceName, bundleID]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (NSString *)postiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services
{
  NSUInteger timestamp = (NSUInteger) NSDate.date.timeIntervalSince1970;
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBTargetSettingsService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 1, NULL, NULL, NULL, 'UNUSED', NULL, NULL, %lu)", serviceName, bundleID, timestamp]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (NSString *)postiOS15ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services
{
  NSUInteger timestamp = (NSUInteger) NSDate.date.timeIntervalSince1970;
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBTargetSettingsService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      // The first 2 is for auth_value, 2 corresponds to "allowed"
      // The other two 2 and 2 that we set here correspond to auth_reason and auth_version
      // Both has to be 2 for  AVCaptureDevice.authorizationStatus(... to return something different from notDetermined
      // It is also possible that in the future auth_version has to be bumped up to 3 and above with newer minor version of iOS
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, %lu)", serviceName, bundleID, timestamp]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (NSString *)postiOS17ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services
{
  NSUInteger timestamp = (NSUInteger) NSDate.date.timeIntervalSince1970;
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBTargetSettingsService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      // iOS 17 access table schema:
      //   CREATE TABLE access (
      //     service        TEXT        NOT NULL,
      //     client         TEXT        NOT NULL,
      //     client_type    INTEGER     NOT NULL,
      //     auth_value     INTEGER     NOT NULL,
      //     auth_reason    INTEGER     NOT NULL,
      //     auth_version   INTEGER     NOT NULL,
      //     csreq          BLOB,
      //     policy_id      INTEGER,
      //     indirect_object_identifier_type    INTEGER,
      //     indirect_object_identifier         TEXT NOT NULL DEFAULT 'UNUSED',
      //     indirect_object_code_identity      BLOB,
      //     flags          INTEGER,
      //     last_modified  INTEGER     NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
      //     pid            INTEGER,
      //     pid_version    INTEGER,
      //     boot_uuid      TEXT NOT NULL DEFAULT 'UNUSED',
      //     last_reminded  INTEGER     NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
      //     PRIMARY KEY (service, client, client_type, indirect_object_identifier),
      //     FOREIGN KEY (policy_id) REFERENCES policies(id) ON DELETE CASCADE ON UPDATE CASCADE
      //   );

      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 2, 2, 2, NULL, NULL, NULL, 'UNUSED', NULL, NULL, %lu, NULL, NULL, 'UNUSED', %lu)", serviceName, bundleID, timestamp, timestamp]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (FBFuture<NSString *> *)runSqliteCommandOnDatabase:(NSString *)databasePath arguments:(NSArray<NSString *> *)arguments queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  arguments = [@[databasePath] arrayByAddingObjectsFromArray:arguments];
  [logger logFormat:@"Running sqlite3 %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];
  return [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/sqlite3" arguments:arguments]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithArray:@[@0, @1]]]
    onQueue:queue fmap:^(FBSubprocess<NSNull *, NSString *, NSString *> *task) {
      if (![task.exitCode.result isEqualToNumber:@0]) {
          return [[FBSimulatorError
            describeFormat:@"Task did not exit 0: %@ %@ %@", task.exitCode.result, task.stdOut, task.stdErr]
            failFuture];
      }
      if ([task.stdErr hasPrefix:@"Error"]) {
        return [[FBSimulatorError
          describeFormat:@"Failed to execute sqlite command: %@", task.stdErr]
          failFuture];
      }
      return [FBFuture futureWithResult:task.stdOut];
    }];
}

+ (NSArray<NSString *> *)contactsDatabaseFilePathsFromContainingDirectory:(NSString *)databaseDirectory error:(NSError **)error
{
  NSMutableArray<NSString *> *filePaths = [NSMutableArray array];
  NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:databaseDirectory];
  NSSet<NSString *> *permissibleDatabaseFilepaths = FBSimulatorSettingsCommands.permissibleAddressBookDBFilenames;

  for (NSString *path in enumerator) {
    if (![permissibleDatabaseFilepaths containsObject:path.lastPathComponent]) {
      continue;
    }
    NSString *fullPath = [databaseDirectory stringByAppendingPathComponent:path];
    [filePaths addObject:fullPath];
  }

  // Fail if nothing is provided
  if (!filePaths.count) {
    return [[FBSimulatorError
      describe:@"Could not update Address Book DBs when no databases are provided"]
      fail:error];
  }

  return [filePaths copy];
}

//Add magic strings to our plist. This is necessary to skip the dialog when using `idb open`
+ (NSString *)magicDeeplinkKeyForScheme:(NSString *)scheme {
  return [NSString stringWithFormat:@"com.apple.CoreSimulator.CoreSimulatorBridge-->%@", scheme];
}

@end
