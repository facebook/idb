/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBBatchLogSearch.h"

#import "FBCollectionInformation.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBControlCoreError.h"
#import "FBDiagnostic.h"
#import "NSPredicate+FBControlCore.h"
#import "FBLogSearch.h"

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

#pragma mark Public Methods

- (NSArray<NSString *> *)allMatches
{
  return [self.mapping.allValues valueForKeyPath:@"@unionOfArrays.self"];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  id mapping = [coder decodeObjectForKey:NSStringFromSelector(@selector(mapping))];
  return [self initWithMapping:mapping];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.mapping forKey:NSStringFromSelector(@selector(mapping))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBBatchLogSearchResult alloc] initWithMapping:self.mapping];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return self.mapping;
}

#pragma mark FBDebugDescribeable Implementation

- (NSString *)description
{
  return self.shortDescription;
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Batch Search Result: %@",
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.mapping]
  ];
}

- (NSString *)debugDescription
{
  return self.shortDescription;
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

@end

@interface FBBatchLogSearch ()

@property (nonatomic, copy, readonly) NSDictionary *mapping;
@property (nonatomic, assign, readonly) FBBatchLogSearchOptions options;

@end

@implementation FBBatchLogSearch

static NSString *const KeyLines = @"lines";
static NSString *const KeyFirst = @"first";
static NSString *const KeyMapping = @"mapping";

#pragma mark Initializers

+ (instancetype)withMapping:(NSDictionary<NSArray<FBDiagnosticName> *, NSArray<FBLogSearchPredicate *> *> *)mapping options:(FBBatchLogSearchOptions)options error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:mapping keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an dictionary<string, string>", mapping] fail:error];
  }

  for (id value in mapping.allValues) {
    if (![FBCollectionInformation isArrayHeterogeneous:value withClass:FBLogSearchPredicate.class]) {
      return [[FBControlCoreError describeFormat:@"%@ value is not an array of log search predicates", value] fail:error];
    }
  }
  return [[FBBatchLogSearch alloc] initWithMapping:mapping options:options];
}

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
  return [self withMapping:[predicateMapping copy] options:options error:error];
}

- (instancetype)initWithMapping:(NSDictionary *)mapping options:(FBBatchLogSearchOptions)options
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = mapping;
  _options = options;

  return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = [coder decodeObjectForKey:KeyMapping];
  _options = (NSUInteger) [coder decodeIntegerForKey:NSStringFromSelector(@selector(options))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.mapping forKey:KeyMapping];
  [coder encodeInteger:(NSInteger)self.options forKey:NSStringFromSelector(@selector(options))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary *mappingDictionary = [NSMutableDictionary dictionary];
  for (NSArray *key in self.mapping) {
    mappingDictionary[key] = [self.mapping[key] valueForKey:@"jsonSerializableRepresentation"];
  }
  BOOL lines = self.options & FBBatchLogSearchOptionsFullLines;
  BOOL first = self.options & FBBatchLogSearchOptionsFirstMatch;
  return @{
    KeyLines: @(lines),
    KeyFirst: @(first),
    KeyMapping: [mappingDictionary copy],
  };
}

#pragma mark FBDebugDescribeable Implementation

- (NSString *)description
{
  return self.shortDescription;
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Batch Search: %@",
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.mapping]
  ];
}

- (NSString *)debugDescription
{
  return self.shortDescription;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBatchLogSearch *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == object.options && [self.mapping isEqualToDictionary:object.mapping];
}

- (NSUInteger)hash
{
  return (NSUInteger) self.options ^ self.mapping.hash;
}

#pragma mark Public API

- (FBBatchLogSearchResult *)search:(NSArray<FBDiagnostic *> *)diagnostics
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

+ (NSDictionary *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics withPredicate:(FBLogSearchPredicate *)predicate options:(FBBatchLogSearchOptions)options
{
  return [[[self withMapping:@{@[] : @[predicate]} options:options error:nil] search:diagnostics] mapping];
}

+ (NSArray<NSString *> *)search:(FBDiagnosticLogSearch *)search withOptions:(FBBatchLogSearchOptions)options
{
  BOOL lines = options & FBBatchLogSearchOptionsFullLines;
  BOOL first = options & FBBatchLogSearchOptionsFirstMatch;
  if (first) {
    NSString *line = lines ? search.firstMatchingLine : search.firstMatch;
    return line ? @[line] : @[];
  } else {
    return lines ? search.matchingLines : search.allMatches;
  }
}

@end
