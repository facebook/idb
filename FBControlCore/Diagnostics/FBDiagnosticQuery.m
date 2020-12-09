/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDiagnosticQuery.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreError.h"
#import "FBDiagnostic.h"
#import "FBEventReporter.h"
#import "FBiOSTargetDiagnostics.h"
#import "FBEventReporterSubject.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeDiagnosticQuery = @"diagnose";

FBDiagnosticQueryFormat FBDiagnosticQueryFormatCurrent = @"current-format";
FBDiagnosticQueryFormat FBDiagnosticQueryFormatPath = @"path";
FBDiagnosticQueryFormat FBDiagnosticQueryFormatContent = @"content";

typedef NSString *FBDiagnosticQueryType NS_STRING_ENUM;
FBDiagnosticQueryType FBDiagnosticQueryTypeAll = @"all";
FBDiagnosticQueryType FBDiagnosticQueryTypeAppFiles = @"app_files";
FBDiagnosticQueryType FBDiagnosticQueryTypeCrashes = @"crashes";
FBDiagnosticQueryType FBDiagnosticQueryTypeNamed = @"named";

@interface FBDiagnosticQuery ()

- (instancetype)initWithQueryFormat:(FBDiagnosticQueryFormat)format;

@end

@interface FBDiagnosticQuery_All : FBDiagnosticQuery

@end

@interface FBDiagnosticQuery_Named : FBDiagnosticQuery

@property (nonatomic, copy, readonly, nonnull) NSArray<NSString *> *names;

@end

@interface FBDiagnosticQuery_Crashes : FBDiagnosticQuery

@property (nonatomic, assign, readonly) FBCrashLogInfoProcessType processType;
@property (nonatomic, copy, readonly, nonnull) NSDate *date;

@end

@implementation FBDiagnosticQuery_All

#pragma mark Initializers

- (instancetype)withFormat:(FBDiagnosticQueryFormat)format
{
  return [[self.class alloc] initWithQueryFormat:format];
}

#pragma mark NSObject

- (NSString *)description
{
  return @"All Logs";
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json format:(FBDiagnosticQueryFormat)format error:(NSError **)error
{
  return [FBDiagnosticQuery_All new];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeAll,
  };
}

#pragma mark Private

- (FBFuture<NSArray<FBDiagnostic *> *> *)run:(id<FBiOSTarget>)target
{
  return [FBFuture futureWithResult:[target.diagnostics allDiagnostics]];
}

@end

@implementation FBDiagnosticQuery_Named

#pragma mark Initializers

- (instancetype)initWithQueryFormat:(FBDiagnosticQueryFormat)format names:(nonnull NSArray<NSString *> *)names
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _names = names;
  return self;
}

- (instancetype)withFormat:(FBDiagnosticQueryFormat)format
{
  return [[self.class alloc] initWithQueryFormat:format names:_names];
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

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Logs Named %@",
    [FBCollectionInformation oneLineDescriptionFromArray:self.names]
  ];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json format:(FBDiagnosticQueryFormat)format error:(NSError **)error
{
  NSArray<NSString *> *names = json[@"names"];
  if (![FBCollectionInformation isArrayHeterogeneous:names withClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSArray<NSString *> for 'names'", names] fail:error];
  }
  return [[self alloc] initWithQueryFormat:format names:names];
}

- (id)jsonSerializableRepresentation
{
  return @{
    @"type" : FBDiagnosticQueryTypeNamed,
    @"names" : self.names,
  };
}

#pragma mark Private

- (FBFuture<NSArray<FBDiagnostic *> *> *)run:(id<FBiOSTarget>)target
{
  NSArray<FBDiagnostic *> *diagnostics = [[[target.diagnostics
    namedDiagnostics]
    objectsForKeys:self.names notFoundMarker:(id)NSNull.null]
    filteredArrayUsingPredicate:NSPredicate.notNullPredicate];
  return [FBFuture futureWithResult:diagnostics];
}

@end

@implementation FBDiagnosticQuery_Crashes

#pragma mark Initializers

- (instancetype)initWithQueryFormat:(FBDiagnosticQueryFormat)format processType:(FBCrashLogInfoProcessType)processType since:(nonnull NSDate *)date
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processType = processType;
  _date = date;

  return self;
}

- (instancetype)withFormat:(FBDiagnosticQueryFormat)format
{
  return [[self.class alloc] initWithQueryFormat:format processType:_processType since:_date];
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

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Crashes %@ %@",
    [FBCollectionInformation oneLineDescriptionFromArray:[FBDiagnosticQuery_Crashes typeStringsFromProcessType:self.processType]],
    self.date
  ];
}

#pragma mark JSON

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json format:(FBDiagnosticQueryFormat)format error:(NSError **)error
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

  return [[self alloc] initWithQueryFormat:format processType:processType since:date];
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

- (FBFuture<NSArray<FBDiagnostic *> *> *)run:(id<FBiOSTarget>)target
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateNewerThanDate:self.date],
  ]];
  return [[target
    crashes:predicate useCache:NO]
    onQueue:target.asyncQueue map:^(NSArray<FBCrashLogInfo *> *crashes) {
      NSMutableArray<FBDiagnostic *> *diagnostics = [NSMutableArray array];
      for (FBCrashLogInfo *crash in crashes) {
        FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder.builder
          updateShortName:crash.crashPath.lastPathComponent]
          updatePath:crash.crashPath]
          build];
        [diagnostics addObject:diagnostic];
      }
      return diagnostics;
    }];
}

@end

@implementation FBDiagnosticQuery

#pragma mark Initializers

+ (nonnull instancetype)named:(nonnull NSArray<NSString *> *)names
{
  return [[FBDiagnosticQuery_Named alloc] initWithQueryFormat:FBDiagnosticQueryFormatCurrent names:names];
}

+ (nonnull instancetype)all
{
  return [FBDiagnosticQuery_All new];
}

+ (nonnull instancetype)crashesOfType:(FBCrashLogInfoProcessType)processType since:(nonnull NSDate *)date
{
  return [[FBDiagnosticQuery_Crashes alloc] initWithQueryFormat:FBDiagnosticQueryFormatCurrent processType:processType since:date];
}

- (instancetype)initWithQueryFormat:(FBDiagnosticQueryFormat)format
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _format = format;
  return self;
}

- (instancetype)withFormat:(FBDiagnosticQueryFormat)format
{
  NSAssert(NO, @"%@ is abstract", NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBDiagnosticQuery *)object
{
  return [object isKindOfClass:self.class];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

static NSString *KeyFormat = @"format";
static NSString *KeyType = @"type";

+ (NSSet<FBDiagnosticQueryFormat> *)validFormats
{
  static dispatch_once_t onceToken;
  static NSSet<FBDiagnosticQueryFormat> *formats;
  dispatch_once(&onceToken, ^{
    formats = [NSSet setWithArray:@[FBDiagnosticQueryFormatCurrent, FBDiagnosticQueryFormatContent, FBDiagnosticQueryFormatPath]];
  });
  return formats;
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a NSDictionary<NSString, id>", json] fail:error];
  }
  FBDiagnosticQueryFormat format = json[KeyFormat] ?: FBDiagnosticQueryFormatCurrent;
  if (![format isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", format, KeyFormat]
      fail:error];
  }
  if (![self.validFormats containsObject:format]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not one of %@", format, [FBCollectionInformation oneLineDescriptionFromArray:self.validFormats.allObjects]]
      fail:error];
  }

  FBDiagnosticQueryType type = json[KeyType];
  if ([type isEqualToString:FBDiagnosticQueryTypeAll]) {
    return [FBDiagnosticQuery_All new];
  }
  if ([type isEqualToString:FBDiagnosticQueryTypeNamed] ) {
    return [FBDiagnosticQuery_Named inflateFromJSON:json format:format error:error];
  }
  if ([type isEqualToString:FBDiagnosticQueryTypeCrashes]) {
    return [FBDiagnosticQuery_Crashes inflateFromJSON:json format:format error:error];
  }
  return [[FBControlCoreError describe:@"%@ is not a valid type"] fail:error];
}

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json format:(FBDiagnosticQueryFormat)format error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeDiagnosticQuery;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBEventReporterSubject> startSubject = [FBEventReporterSubject subjectWithName:FBiOSTargetFutureTypeDiagnosticQuery type:FBEventTypeStarted value:self];
  [reporter report:startSubject];

  return [[self
    run:target]
    onQueue:target.workQueue map:^(NSArray<FBDiagnostic *> *diagnostics) {
      id<FBEventReporterSubject> subject = [FBDiagnosticQuery resolveDiagnostics:diagnostics format:self.format];
      [reporter report:subject];

      subject = [FBEventReporterSubject subjectWithName:FBiOSTargetFutureTypeDiagnosticQuery type:FBEventTypeEnded value:self ];
      [reporter report:subject];

      return FBiOSTargetContinuationDone(FBDiagnosticQuery.futureType);
    }];
}

+ (id<FBEventReporterSubject>)resolveDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics format:(FBDiagnosticQueryFormat)format
{
  NSMutableArray<id<FBEventReporterSubject>> *subjects = [NSMutableArray array];
  for (FBDiagnostic *diagnostic in diagnostics) {
    FBDiagnostic *resolved = diagnostic;
    if ([format isEqualToString:FBDiagnosticQueryFormatContent]) {
      resolved = [[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic] readIntoMemory] build];
    } else if ([format isEqualToString:FBDiagnosticQueryFormatPath]) {
      resolved = [[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic] writeOutToFile] build];
    }
    [subjects addObject:[FBEventReporterSubject subjectWithName:FBEventNameDiagnostic type:FBEventTypeDiscrete value:resolved]];
  }
  return [FBEventReporterSubject compositeSubjectWithArray:subjects];
}

#pragma mark Private

- (NSArray<FBDiagnostic *> *)run:(FBiOSTargetDiagnostics *)diagnostics
{
  return @[];
}

@end
