/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBatchLogSearch.h"

#import "FBCollectionInformation.h"
#import "FBCollectionOperations.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBiOSTargetConfiguration.h"
#import "FBControlCoreError.h"
#import "FBDiagnostic.h"
#import "FBEventReporter.h"
#import "FBLogCommands.h"
#import "FBLogSearch.h"
#import "FBEventReporterSubject.h"
#import "FBiOSTarget.h"
#import "FBiOSTargetDiagnostics.h"
#import "NSPredicate+FBControlCore.h"
#import "FBFuture+Sync.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeSearch = @"search";

@implementation FBBatchLogSearchResult

#pragma mark Initializers

- (instancetype)initWithMapping:(NSDictionary<FBDiagnosticName, NSArray<NSString *> *> *)mapping
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = mapping;

  return self;
}

#pragma mark Public Methods

- (NSArray<NSString *> *)allMatches
{
  return [self.mapping.allValues valueForKeyPath:@"@unionOfArrays.self"];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBBatchLogSearchResult alloc] initWithMapping:self.mapping];
}

#pragma mark JSON Conversion

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describe:@"%@ is not an NSDictionary<NSString, NSArray>"] fail:error];
  }
  for (NSArray *results in json.allValues) {
    if (![FBCollectionInformation isArrayHeterogeneous:results withClass:NSString.class]) {
      return [[FBControlCoreError describe:@"%@ is not an NSArray<NSString>"] fail:error];
    }
  }
  return [[self alloc] initWithMapping:json];
}

- (id)jsonSerializableRepresentation
{
  return self.mapping;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBatchLogSearchResult *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.mapping isEqualToDictionary:object.mapping];
}

- (NSUInteger)hash
{
  return self.mapping.hash;
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Batch Search Result: %@",
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.mapping]
  ];
}

@end

@implementation FBBatchLogSearch

static NSString *const KeyLines = @"lines";
static NSString *const KeyFirst = @"first";
static NSString *const KeyMapping = @"mapping";
static NSString *const KeySince = @"since";

#pragma mark Initializers

+ (instancetype)searchWithMapping:(NSDictionary<FBDiagnosticName, NSArray<FBLogSearchPredicate *> *> *)mapping options:(FBBatchLogSearchOptions)options since:(nullable NSDate *)since error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:mapping keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an dictionary<string, string>", mapping] fail:error];
  }

  for (id value in mapping.allValues) {
    if (![FBCollectionInformation isArrayHeterogeneous:value withClass:FBLogSearchPredicate.class]) {
      return [[FBControlCoreError describeFormat:@"%@ value is not an array of log search predicates", value] fail:error];
    }
  }
  return [[FBBatchLogSearch alloc] initWithMapping:mapping options:options since:since];
}

- (instancetype)initWithMapping:(NSDictionary *)mapping options:(FBBatchLogSearchOptions)options since:(nullable NSDate *)since
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = mapping;
  _options = options;
  _since = since;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON Conversion

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![json isKindOfClass:NSDictionary.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary", json] fail:error];
  }
  NSNumber *lines = json[KeyLines] ?: @NO;
  if (![lines isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a number for '%@'", lines, KeyLines]
      fail:error];
  }
  NSNumber *first = json[KeyFirst] ?: @NO;
  if (![lines isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a number for '%@'", lines, KeyFirst]
      fail:error];
  }
  FBBatchLogSearchOptions options = 0;
  if (lines.boolValue) {
    options = options | FBBatchLogSearchOptionsFullLines;
  }
  if (first.boolValue) {
    options = options | FBBatchLogSearchOptionsFirstMatch;
  }
  NSNumber *sinceTimestamp = [FBCollectionOperations nullableValueForDictionary:json key:KeySince] ?: nil;
  if (sinceTimestamp && ![sinceTimestamp isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a timestamp for '%@'", sinceTimestamp, KeySince]
      fail:error];
  }
  NSDate *since = sinceTimestamp ? [NSDate dateWithTimeIntervalSince1970:sinceTimestamp.doubleValue] : nil;

  NSDictionary<NSString *, NSArray *> *jsonMapping = json[KeyMapping];
  if (![FBCollectionInformation isDictionaryHeterogeneous:jsonMapping keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a dictionary of <string, array> for '%@'", jsonMapping, KeyMapping]
      fail:error];
  }

  NSMutableDictionary *predicateMapping = [NSMutableDictionary dictionary];
  for (NSString *key in jsonMapping.allKeys) {
    NSMutableArray *predicates = [NSMutableArray array];
    for (NSDictionary *predicateJSON in jsonMapping[key]) {
      FBLogSearchPredicate *predicate = [FBLogSearchPredicate inflateFromJSON:predicateJSON error:error];
      if (!predicate) {
        return [[FBControlCoreError describeFormat:@"%@ is not a predicate", predicateJSON] fail:error];
      }
      [predicates addObject:predicate];
    }

    predicateMapping[key] = [predicates copy];
  }
  return [self searchWithMapping:[predicateMapping copy] options:options since:since error:error];
}

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary *mappingDictionary = [NSMutableDictionary dictionary];
  for (FBDiagnosticName key in self.mapping) {
    mappingDictionary[key] = [self.mapping[key] valueForKey:@"jsonSerializableRepresentation"];
  }
  BOOL lines = (self.options & FBBatchLogSearchOptionsFullLines) != 0;
  BOOL first = (self.options & FBBatchLogSearchOptionsFirstMatch) != 0;
  return @{
    KeyLines: @(lines),
    KeyFirst: @(first),
    KeyMapping: [mappingDictionary copy],
    KeySince: self.since ? @(self.since.timeIntervalSince1970) : NSNull.null,
  };
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBatchLogSearch *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == object.options &&
         [self.mapping isEqualToDictionary:object.mapping] &&
         (self.since == object.since || [self.since isEqualToDate:object.since]);
}

- (NSUInteger)hash
{
  return (NSUInteger) self.options ^ self.mapping.hash ^ self.since.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Batch Search: %@",
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.mapping]
  ];
}

#pragma mark Public API

- (FBBatchLogSearchResult *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics
{
  NSParameterAssert([FBCollectionInformation isArrayHeterogeneous:diagnostics withClass:FBDiagnostic.class]);

  // Construct an NSDictionary<FBDiagnosticName, FBDiagnostic> of diagnostics.
  NSDictionary *namesToDiagnostics = [NSDictionary dictionaryWithObjects:diagnostics forKeys:[diagnostics valueForKey:@"shortName"]];

  // Construct and NSArray<FBLogSearch> instances
  NSMutableArray *searchers = [NSMutableArray array];
  for (NSString *diagnosticName in self.mapping.allKeys) {
    NSArray *predicates = self.mapping[diagnosticName];

    if ([diagnosticName isEqualToString:@""]) {
      for (FBDiagnostic *diagnostic in diagnostics) {
        for (FBLogSearchPredicate *predicate in predicates) {
          [searchers addObject:[FBDiagnosticLogSearch withDiagnostic:diagnostic predicate:predicate]];
        }
      }
    }
    FBDiagnostic *diagnostic = namesToDiagnostics[diagnosticName];
    if (!diagnostic) {
      continue;
    }
    for (FBLogSearchPredicate *predicate in predicates) {
      [searchers addObject:[FBDiagnosticLogSearch withDiagnostic:diagnostic predicate:predicate]];
    }
  }

  // Perform the search, concurrently
  FBBatchLogSearchOptions options = self.options;
  NSArray<NSArray *> *results = [FBConcurrentCollectionOperations
    mapFilter:[searchers copy]
    map:^ NSArray * (FBDiagnosticLogSearch *search) {
      NSArray<NSString *> *matches = [FBBatchLogSearch search:search withOptions:options];
      if (matches.count == 0) {
       return nil;
      }
      return @[search.diagnostic.shortName, matches];
    }
    predicate:NSPredicate.notNullPredicate];

  // Rebuild the output dictionary
  NSMutableDictionary *output = [NSMutableDictionary dictionary];
  for (NSArray *result in results) {
    NSString *key = result[0];
    NSArray<NSString *> *values = result[1];
    NSMutableArray<NSString *> *matches = output[key];
    if (!matches) {
      matches = [NSMutableArray array];
      output[key] = matches;
    }
    [matches addObjectsFromArray:values];
  }

  // The JSON Inflation will check the format, so is a sanity chek on the data structure.
  FBBatchLogSearchResult *result = [FBBatchLogSearchResult inflateFromJSON:[output copy] error:nil];
  NSAssert(result != nil, @"%@ search result should be well-formed, but isn't", output);
  return result;
}

- (FBFuture<FBBatchLogSearchResult *> *)searchOnTarget:(id<FBiOSTarget>)target
{
  // Only use the specialized logging on iOS.
    if (target.deviceType.family != FBControlCoreProductFamilyiPhone && target.deviceType.family != FBControlCoreProductFamilyiPad) {
    return [FBFuture futureWithResult:[self searchDiagnostics:target.diagnostics.allDiagnostics]];
  }
  // Only use specialized logging on iOS 11 or greater.
  if ([target.osVersion.number compare:[NSDecimalNumber numberWithInt:11]] == NSOrderedAscending) {
    return [FBFuture futureWithResult:[self searchDiagnostics:target.diagnostics.allDiagnostics]];
  }
  // Perform a special search using the log commands, if the search is relevant.
  id<FBLogCommands> log = (id<FBLogCommands>) target;
  if (![log conformsToProtocol:@protocol(FBLogCommands)]) {
    return [FBFuture futureWithResult:[self searchDiagnostics:target.diagnostics.allDiagnostics]];
  }
  // Only perform if we only care about the syslog
  if (![self.mapping.allKeys isEqualToArray:@[FBDiagnosticNameSyslog]]) {
    return [FBFuture futureWithResult:[self searchDiagnostics:target.diagnostics.allDiagnostics]];
  }
  // Also, the search must represent a compilable predicate for the command.
  NSArray<NSString *> *arguments = [self.class argumentsForLogCommand:self.mapping[FBDiagnosticNameSyslog] since:self.since error:nil];
  if (!arguments) {
    return [FBFuture futureWithResult:[self searchDiagnostics:target.diagnostics.allDiagnostics]];
  }
  return [[log
    logLinesWithArguments:arguments]
    onQueue:target.asyncQueue map:^(NSArray<NSString *> *lines) {
      return [[FBBatchLogSearchResult alloc] initWithMapping:@{
         FBDiagnosticNameSyslog: lines,
      }];
    }];
}

+ (NSDictionary<FBDiagnosticName, NSArray<NSString *> *> *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics withPredicate:(FBLogSearchPredicate *)predicate options:(FBBatchLogSearchOptions)options
{
  return [[[self
    searchWithMapping:@{@"" : @[predicate]} options:options since:nil error:nil]
    searchDiagnostics:diagnostics]
    mapping];
}

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeSearch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  FBiOSTargetFutureType futureType = self.class.futureType;
  return [[self
    searchOnTarget:target]
    onQueue:target.workQueue map:^FBFuture *(FBBatchLogSearchResult *result) {
      id<FBEventReporterSubject> subject = [FBEventReporterSubject subjectWithName:futureType type:FBEventTypeDiscrete value:result];
      [reporter report:subject];
      return FBiOSTargetContinuationDone(futureType);
    }];
}

#pragma mark Private

+ (NSDateFormatter *)logCommandDateFormatter
{
  static dispatch_once_t onceToken;
  static NSDateFormatter *dateFormatter;
  dispatch_once(&onceToken, ^{
    dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  });
  return dateFormatter;
}

+ (NSArray<NSString *> *)search:(FBDiagnosticLogSearch *)search withOptions:(FBBatchLogSearchOptions)options
{
  BOOL lines = (options & FBBatchLogSearchOptionsFullLines) != 0;
  BOOL first = (options & FBBatchLogSearchOptionsFirstMatch) != 0;
  if (first) {
    NSString *line = lines ? search.firstMatchingLine : search.firstMatch;
    return line ? @[line] : @[];
  } else {
    return lines ? search.matchingLines : search.allMatches;
  }
}

+ (NSArray<NSString *> *)argumentsForLogCommand:(NSArray<FBLogSearchPredicate *> *)predicates since:(nullable NSDate *)since error:(NSError **)error
{
  NSString *compiled = [FBLogSearchPredicate logAgumentsFromPredicates:predicates error:error];
  if (!compiled) {
    return nil;
  }
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:@"show"];
  if (since) {
    [arguments addObjectsFromArray:@[
       @"--start", [FBBatchLogSearch.logCommandDateFormatter stringFromDate:since],
    ]];
  }
  [arguments addObjectsFromArray:@[
     @"--predicate", compiled,
  ]];
  return arguments;
}

@end
