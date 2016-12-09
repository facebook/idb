/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDiagnosticQuery.h"

#import "FBDiagnostic.h"
#import "FBControlCoreError.h"

static NSString *const FBDiagnosticQueryTypeAll = @"all";
static NSString *const FBDiagnosticQueryTypeAppFiles = @"app_files";
static NSString *const FBDiagnosticQueryTypeCrashes = @"crashes";
static NSString *const FBDiagnosticQueryTypeNamed = @"named";


@implementation FBDiagnosticQuery_All

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  return [FBDiagnosticQuery_All new];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeAll,
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return @"All Logs";
}

@end

@implementation FBDiagnosticQuery_Named

#pragma mark Initializers

- (instancetype)initWithNames:(nonnull NSArray<NSString *> *)names
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _names = names;
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnosticQuery_Named *)object
{
  return [super isEqual:object] && [self.names isEqualToArray:object.names];
}

- (NSUInteger)hash
{
  return self.names.hash;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithNames:self.names];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  _names = [coder decodeObjectForKey:NSStringFromSelector(@selector(names))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.names forKey:NSStringFromSelector(@selector(names))];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSArray<NSString *> *names = json[@"names"];
  if (![FBCollectionInformation isArrayHeterogeneous:names withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSArray<NSString *> for 'names'", names] fail:error];
  }
  return [[self alloc] initWithNames:names];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeNamed,
    @"names" : self.names,
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Logs Named %@",
    [FBCollectionInformation oneLineDescriptionFromArray:self.names]
  ];
}

@end

@implementation FBDiagnosticQuery_ApplicationLogs

#pragma mark Initializers

- (instancetype)initWithBundleID:(nonnull NSString *)bundleID filenames:(nonnull NSArray<NSString *> *)filenames
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;
  _filenames = filenames;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnosticQuery_ApplicationLogs *)object
{
  return [super isEqual:object] && [self.bundleID isEqualToString:object.bundleID] && [self.filenames isEqualToArray:object.filenames];
}

- (NSUInteger)hash
{
  return self.bundleID.hash ^ self.filenames.hash;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithBundleID:self.bundleID filenames:self.filenames];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  _bundleID = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleID))];
  _filenames = [coder decodeObjectForKey:NSStringFromSelector(@selector(filenames))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.filenames forKey:NSStringFromSelector(@selector(filenames))];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSArray<NSString *> *filenames = json[@"filenames"];
  if (![FBCollectionInformation isArrayHeterogeneous:filenames withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSArray<NSString *> for 'filenames'", filenames] fail:error];
  }
  NSString *bundleID = json[@"bundle_id"];
  if (![bundleID isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a String for 'bundle_id'", bundleID] fail:error];
  }

  return [[self alloc] initWithBundleID:bundleID filenames:filenames];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeAppFiles,
    @"bundle_id" : self.bundleID,
    @"filenames" : self.filenames,
  };
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"App Logs %@ %@",
    self.bundleID,
    [FBCollectionInformation oneLineDescriptionFromArray:self.filenames]
  ];
}

@end

@implementation FBDiagnosticQuery_Crashes

#pragma mark Initializers

- (instancetype)initWithProcessType:(FBCrashLogInfoProcessType)processType since:(nonnull NSDate *)date
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processType = processType;
  _date = date;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnosticQuery_Crashes *)object
{
  return [super isEqual:object] && self.processType == object.processType && [self.date isEqual:object.date];
}

- (NSUInteger)hash
{
  return self.processType ^ self.date.hash;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc] initWithProcessType:self.processType since:self.date];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (!self) {
    return nil;
  }

  _processType = [[coder decodeObjectForKey:NSStringFromSelector(@selector(processType))] unsignedIntegerValue];
  _date = [coder decodeObjectForKey:NSStringFromSelector(@selector(date))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [super encodeWithCoder:coder];
  [coder encodeObject:@(self.processType) forKey:NSStringFromSelector(@selector(processType))];
  [coder encodeObject:self.date forKey:NSStringFromSelector(@selector(date))];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  NSArray<NSString *> *typeStrings = json[@"process_types"];
  if (![FBCollectionInformation isArrayHeterogeneous:typeStrings withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSArray<NSString *> for 'process_types'", typeStrings] fail:error];
  }
  FBCrashLogInfoProcessType processType = [FBDiagnosticQuery_Crashes processTypeFromTypeStrings:typeStrings];

  NSNumber *timestamp = json[@"since"];
  if (![timestamp isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a unix timestamp for 'since'", timestamp] fail:error];
  }
  NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];

  return [[self alloc] initWithProcessType:processType since:date];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeCrashes,
    @"since" : @(self.date.timeIntervalSince1970),
    @"process_types" : [FBDiagnosticQuery_Crashes typeStringsFromProcessType:self.processType],
  };
}

#pragma mark Private

static NSString *const FBDiagnosticQueryCrashesApplication = @"application";
static NSString *const FBDiagnosticQueryCrashesCustomAgent = @"custom_agent";
static NSString *const FBDiagnosticQueryCrashesSystem = @"system";

+ (nonnull NSArray<NSString *> *)typeStringsFromProcessType:(FBCrashLogInfoProcessType)processType
{
  NSMutableArray<NSString *> *array = [NSMutableArray array];
  if ((processType & FBCrashLogInfoProcessTypeApplication) == FBCrashLogInfoProcessTypeApplication) {
    [array addObject:FBDiagnosticQueryCrashesApplication];
  }
  if ((processType & FBCrashLogInfoProcessTypeCustomAgent) == FBCrashLogInfoProcessTypeCustomAgent) {
    [array addObject:FBDiagnosticQueryCrashesCustomAgent];
  }
  if ((processType & FBCrashLogInfoProcessTypeSystem) == processType) {
    [array addObject:FBDiagnosticQueryCrashesSystem];
  }
  return [array copy];
}

+ (FBCrashLogInfoProcessType)processTypeFromTypeStrings:(nonnull NSArray<NSString *> *)typeStrings
{
  NSSet<NSString *> *set = [NSSet setWithArray:typeStrings];
  FBCrashLogInfoProcessType processType = 0;
  if ([set containsObject:FBDiagnosticQueryCrashesApplication]) {
    processType = processType | FBCrashLogInfoProcessTypeApplication;
  }
  if ([set containsObject:FBDiagnosticQueryCrashesCustomAgent]) {
    processType = processType | FBCrashLogInfoProcessTypeCustomAgent;
  }
  if ([set containsObject:FBDiagnosticQueryCrashesSystem]) {
    processType = processType | FBCrashLogInfoProcessTypeSystem;
  }
  return processType;
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Crashes %@ %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[FBDiagnosticQuery_Crashes typeStringsFromProcessType:self.processType]],
    self.date
  ];
}

@end

@implementation FBDiagnosticQuery

#pragma mark Initializers

+ (nonnull instancetype)named:(nonnull NSArray<NSString *> *)names
{
  return [[FBDiagnosticQuery_Named alloc] initWithNames:names];
}

+ (nonnull instancetype)all
{
  return [FBDiagnosticQuery_All new];
}

+ (nonnull instancetype)filesInApplicationOfBundleID:(nonnull NSString *)bundleID withFilenames:(nonnull NSArray<NSString *> *)filenames
{
  return [[FBDiagnosticQuery_ApplicationLogs alloc] initWithBundleID:bundleID filenames:filenames];
}

+ (nonnull instancetype)crashesOfType:(FBCrashLogInfoProcessType)processType since:(nonnull NSDate *)date
{
  return [[FBDiagnosticQuery_Crashes alloc] initWithProcessType:processType since:date];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnosticQuery *)object
{
  return [object isKindOfClass:self.class];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [self init];
  if (!self) {
    return nil;
  }

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{

}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSDictionary<NSString, id>", json] fail:error];
  }
  NSString *type = json[@"type"];
  if ([type isEqualToString:FBDiagnosticQueryTypeAll]) {
    return [FBDiagnosticQuery_All new];
  }
  if ([type isEqualToString:FBDiagnosticQueryTypeNamed] ) {
    return [FBDiagnosticQuery_Named inflateFromJSON:json error:error];
  }
  if ([type isEqualToString:FBDiagnosticQueryTypeCrashes]) {
    return [FBDiagnosticQuery_Crashes inflateFromJSON:json error:error];
  }
  if ([type isEqualToString:FBDiagnosticQueryTypeAppFiles]) {
    return [FBDiagnosticQuery_ApplicationLogs inflateFromJSON:json error:error];
  }
  return [[FBControlCoreError describe:@"%@ is not a valid type"] fail:error];
}

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return self.shortDescription;
}

- (NSString *)shortDescription
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSString *)debugDescription
{
  return self.shortDescription;
}

@end
