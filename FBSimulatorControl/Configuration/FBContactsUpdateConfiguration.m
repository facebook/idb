/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBContactsUpdateConfiguration.h"

#import "FBSimulatorSettingsCommands.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeContactsUpdate = @"contacts_update";

@implementation FBContactsUpdateConfiguration

#pragma mark Initializers

+ (instancetype)configurationWithDatabaseDirectory:(NSString *)databaseDirectory
{
  return [[self alloc] initWithDatabaseDirectory:databaseDirectory];
}

- (instancetype)initWithDatabaseDirectory:(NSString *)databaseDirectory
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _databaseDirectory = databaseDirectory;

  return self;
}

#pragma mark JSON

static NSString *const KeyDatabaseDirectory = @"db_directory";

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ should be a Dictionary<string, object>", json]
      fail:error];
  }
  NSString *directory = json[KeyDatabaseDirectory];
  if (![directory isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an String for %@", directory, KeyDatabaseDirectory]
      fail:error];
  }
  return [self configurationWithDatabaseDirectory:directory];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyDatabaseDirectory: self.databaseDirectory,
  };
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Update Contact Databases %@", self.databaseDirectory];
}

- (BOOL)isEqual:(FBContactsUpdateConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }
  return [self.databaseDirectory isEqualToString:configuration.databaseDirectory];
}

- (NSUInteger)hash
{
  return self.databaseDirectory.hash ^ [NSStringFromClass(self.class) hash];
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeContactsUpdate;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorSettingsCommands> commands = (id<FBSimulatorSettingsCommands>) target;
  if (![target conformsToProtocol:@protocol(FBSimulatorSettingsCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"%@ does not support FBSimulatorSettingsCommands", target]
      failFuture];
  }
  FBiOSTargetFutureType futureType = self.class.futureType;
  return [[commands
    updateContacts:self.databaseDirectory]
    mapReplace:FBiOSTargetContinuationDone(futureType)];
}

@end

