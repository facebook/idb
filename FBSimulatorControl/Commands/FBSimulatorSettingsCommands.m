/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorSettingsCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBDefaultsModificationStrategy.h"
#import "FBSimulator.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeApproval = @"approve";
static NSString *const SpringBoardServiceName = @"com.apple.SpringBoard";

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

- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled
{
  return [[self.simulator
    connectToBridge]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (FBSimulatorBridge *bridge) {
      return [bridge setHardwareKeyboardEnabled:enabled];
    }];
}

- (FBFuture<NSNull *> *)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  if (!localizationOverride) {
    return FBFuture.empty;
  }

  return [[FBLocalizationDefaultsModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideLocalization:localizationOverride];
}

- (FBFuture<NSNull *> *)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout
{
  return [[FBWatchdogOverrideModificationStrategy
    strategyWithSimulator:self.simulator]
    overrideWatchDogTimerForApplications:bundleIDs timeout:timeout];
}

- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services
{
  // We need at least one approval in the input
  if (services.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve any services for %@ since no services were provided", bundleIDs]
      failFuture];
  }
  // We also need at least one bundle id in the input.
  if (services.count == 0) {
    return [[FBSimulatorError
      describeFormat:@"Cannot approve %@ since no bundle ids were provided", services]
      failFuture];
  }

  // Composing different futures due to differences in how these operate.
  NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
  NSMutableSet<NSString *> *toApprove = [NSMutableSet setWithSet:services];

  // Go through each of the internal APIs, removing them from the pending set as we go.
  if ([self.simulator.device respondsToSelector:@selector(setPrivacyAccessForService:bundleID:granted:error:)]) {
    NSMutableSet<NSString *> *simDeviceServices = [toApprove mutableCopy];
    [simDeviceServices intersectSet:[NSSet setWithArray:FBSimulatorSettingsCommands.coreSimulatorSettingMapping.allKeys]];
    // Only approve these services, where they are serviced by the CoreSimulator API
    if (simDeviceServices.count > 0) {
      [toApprove minusSet:simDeviceServices];
      [futures addObject:[self coreSimulatorApproveWithBundleIDs:bundleIDs toServices:simDeviceServices]];
    }
  }
  if (toApprove.count > 0 && [[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys] intersectsSet:toApprove]) {
    NSMutableSet<NSString *> *tccServices = [toApprove mutableCopy];
    [tccServices intersectSet:[NSSet setWithArray:FBSimulatorSettingsCommands.tccDatabaseMapping.allKeys]];
    [toApprove minusSet:tccServices];
    [futures addObject:[self modifyTCCDatabaseWithBundleIDs:bundleIDs toServices:tccServices]];
  }
  if (toApprove.count > 0 && [toApprove containsObject:FBSettingsApprovalServiceLocation]) {
    [futures addObject:[self authorizeLocationSettings:bundleIDs.allObjects]];
    [toApprove removeObject:FBSettingsApprovalServiceLocation];
  }
  if (toApprove.count > 0 && [toApprove containsObject:FBSettingsApprovalServiceNotification]) {
    [futures addObject:[self authorizeNotificationService:bundleIDs.allObjects]];
    [toApprove removeObject:FBSettingsApprovalServiceNotification];
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

  //Add magic strings to our plist. This is necessary to skip the dialog when using `idb open`
  NSString *urlKey = [NSString stringWithFormat:@"com.apple.CoreSimulator.CoreSimulatorBridge-->%@", scheme];
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

- (FBFuture<NSNull *> *)setupKeyboard
{
  return [[FBKeyboardSettingsModificationStrategy
    strategyWithSimulator:self.simulator]
    setupKeyboard];
}

#pragma mark Private

- (FBFuture<NSNull *> *)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs
{
  return [[FBLocationServicesModificationStrategy
    strategyWithSimulator:self.simulator]
    approveLocationServicesForBundleIDs:bundleIDs];
}

- (FBFuture<NSNull *> *)authorizeNotificationService:(NSArray<NSString *> *)bundleIDs
{
  if ([bundleIDs count] == 0) {
    return [[FBSimulatorError
      describe:@"Empty bundleID set provided to notifications approve"]
      failFuture];
  }

  NSString *bulletinDirectory = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Library/BulletinBoard"];
  NSString *notificationsApprovalPlistPath = [bulletinDirectory stringByAppendingPathComponent:@"VersionedSectionInfo.plist"];

  NSMutableDictionary<NSString *, id> *sectionInfo = [NSMutableDictionary dictionaryWithContentsOfFile:notificationsApprovalPlistPath];

  if (sectionInfo == nil) {
    return [[FBSimulatorError
      describe:@"Failed to load sectionInfo"]
      failFuture];
  }

  for (NSString *bundleID in bundleIDs) {
    NSData *data = sectionInfo[@"sectionInfo"][bundleID];
    if (data == nil) {
      data = [[sectionInfo[@"sectionInfo"] allValues] firstObject];
    }

    NSError *readError = nil;
    NSDictionary<NSString *, id> *properties = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:nil error:&readError];
    if (readError != nil) {
      return [FBSimulatorError failFutureWithError:readError];
    }
    properties[@"$objects"][2] = bundleID;
    properties[@"$objects"][3][@"allowsNotifications"] = @(YES);

    NSError *writeError = nil;
    NSData *resultData = [NSPropertyListSerialization dataWithPropertyList:properties format:NSPropertyListBinaryFormat_v1_0 options:0 error:&writeError];
    if (writeError != nil) {
      return [FBSimulatorError failFutureWithError:writeError];
    }
    sectionInfo[@"sectionInfo"][bundleID] = resultData;
  }

  BOOL result = [sectionInfo writeToFile:notificationsApprovalPlistPath atomically:YES];
  if (!result) {
    return [[FBSimulatorError
      describe:@"Failed to write sectionInfo data to plist"]
      failFuture];
  }

  if (self.simulator.state == FBiOSTargetStateBooted) {
    return [[self.simulator stopServiceWithName:SpringBoardServiceName] mapReplace:NSNull.null];
  } else {
    return FBFuture.empty;
  }
}

- (FBFuture<NSNull *> *)modifyTCCDatabaseWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services
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

- (FBFuture<NSNull *> *)coreSimulatorApproveWithBundleIDs:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services
{
  for (NSString *bundleID in bundleIDs) {
    for (NSString *service in services) {
      NSString *internalService = FBSimulatorSettingsCommands.coreSimulatorSettingMapping[service];
      if (!internalService) {
        return [[FBSimulatorError
          describeFormat:@"%@ is not a valid service for CoreSimulator", service]
          failFuture];
      }
      NSError *error = nil;
      if (![self.simulator.device setPrivacyAccessForService:internalService bundleID:bundleID granted:YES error:&error]) {
        return [FBFuture futureWithError:error];
      }
    }
  }
  return FBFuture.empty;
}

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

+ (NSDictionary<FBSettingsApprovalService, NSString *> *)coreSimulatorSettingMapping
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBSettingsApprovalService, NSString *> *mapping;
  dispatch_once(&onceToken, ^{
    mapping = @{
      FBSettingsApprovalServiceContacts: @"kTCCServiceContactsFull",
      FBSettingsApprovalServicePhotos: @"kTCCServicePhotos",
      FBSettingsApprovalServiceCamera: @"camera",
      FBSettingsApprovalServiceLocation: @"__CoreLocationAlways",
      FBSettingsApprovalServiceMicrophone: @"kTCCServiceMicrophone",
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

+ (NSSet<FBSettingsApprovalService> *)filteredTCCApprovals:(NSSet<FBSettingsApprovalService> *)approvals
{
  NSMutableSet<FBSettingsApprovalService> *filtered = [NSMutableSet setWithSet:approvals];
  [filtered intersectSet:[NSSet setWithArray:self.tccDatabaseMapping.allKeys]];
  return [filtered copy];
}

+ (FBFuture<NSString *> *)buildRowsForDatabase:(NSString *)databasePath bundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBSettingsApprovalService> *)services queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSParameterAssert(bundleIDs.count >= 1);
  NSParameterAssert(services.count >= 1);

  return [[self
    runSqliteCommandOnDatabase:databasePath arguments:@[@".schema access"] queue:queue logger:logger]
    onQueue:queue map:^(NSString *result) {
      if ([result containsString:@"last_modified"]) {
        return [FBSimulatorSettingsCommands postiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
      } else {
        return [FBSimulatorSettingsCommands preiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
      }
    }];
}

+ (NSString *)preiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBSettingsApprovalService> *)services
{
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBSettingsApprovalService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 0, 0, 0)", serviceName, bundleID]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (NSString *)postiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBSettingsApprovalService> *)services
{
  NSUInteger timestamp = (NSUInteger) NSDate.date.timeIntervalSince1970;
  NSMutableArray<NSString *> *tuples = [NSMutableArray array];
  for (NSString *bundleID in bundleIDs) {
    for (FBSettingsApprovalService service in [self filteredTCCApprovals:services]) {
      NSString *serviceName = self.tccDatabaseMapping[service];
      [tuples addObject:[NSString stringWithFormat:@"('%@', '%@', 0, 1, 1, NULL, NULL, NULL, 'UNUSED', NULL, NULL, %lu)", serviceName, bundleID, timestamp]];
    }
  }
  return [tuples componentsJoinedByString:@", "];
}

+ (FBFuture<NSString *> *)runSqliteCommandOnDatabase:(NSString *)databasePath arguments:(NSArray<NSString *> *)arguments queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  arguments = [@[databasePath] arrayByAddingObjectsFromArray:arguments];
  [logger logFormat:@"Running sqlite3 %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];
  return [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sqlite3" arguments:arguments]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString]
    withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
    withLoggingTo:logger]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask<NSNull *, NSString *, NSString *> *task) {
      if (![task.exitCode.result isEqualToNumber:@0]) {
          return [[[FBSimulatorError
            describeFormat:@"Task did not exit 0: %@ %@ %@", task.exitCode.result, task.stdOut, task.stdErr]
            logger:logger]
            failFuture];
      }
      if ([task.stdErr hasPrefix:@"Error"]) {
        return [[[FBSimulatorError
          describeFormat:@"Failed to execute sqlite command: %@", task.stdErr]
          logger:logger]
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

@end

@implementation FBSettingsApproval (FBiOSTargetFuture)

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeApproval;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
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
