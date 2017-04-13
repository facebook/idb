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
@property (nonatomic, assign, readonly) BOOL lines;

@end

@implementation FBBatchLogSearch

#pragma mark Initializers

+ (instancetype)withMapping:(NSDictionary<NSArray<FBDiagnosticName> *, NSArray<FBLogSearchPredicate *> *> *)mapping lines:(BOOL)lines error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:mapping keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not an dictionary<string, string>", mapping] fail:error];
  }

  for (id value in mapping.allValues) {
    if (![FBCollectionInformation isArrayHeterogeneous:value withClass:FBLogSearchPredicate.class]) {
      return [[FBControlCoreError describeFormat:@"%@ value is not an array of log search predicates", value] fail:error];
    }
  }
  return [[FBBatchLogSearch alloc] initWithMapping:mapping lines:lines];
}

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![json isKindOfClass:NSDictionary.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary", json] fail:error];
  }
  NSNumber *lines = json[@"lines"];
  if (![lines isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a number for 'lines'", lines] fail:error];
  }

  NSDictionary<NSString *, NSArray *> *jsonMapping = json[@"mapping"];
  if (![FBCollectionInformation isDictionaryHeterogeneous:jsonMapping keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary of <string, array> for 'mapping'", jsonMapping] fail:error];
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
  return [self withMapping:[predicateMapping copy] lines:lines.boolValue error:error];
}

- (instancetype)initWithMapping:(NSDictionary *)mapping lines:(BOOL)lines
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = mapping;
  _lines = lines;

  return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = [coder decodeObjectForKey:NSStringFromSelector(@selector(mapping))];
  _lines = [coder decodeBoolForKey:NSStringFromSelector(@selector(lines))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.mapping forKey:NSStringFromSelector(@selector(mapping))];
  [coder encodeBool:self.lines forKey:NSStringFromSelector(@selector(lines))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBBatchLogSearch alloc] initWithMapping:self.mapping lines:self.lines];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary *mappingDictionary = [NSMutableDictionary dictionary];
  for (NSArray *key in self.mapping) {
    mappingDictionary[key] = [self.mapping[key] valueForKey:@"jsonSerializableRepresentation"];
  }
  return @{
    @"lines" : @(self.lines),
    @"mapping" : [mappingDictionary copy],
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

  return self.lines == object.lines && [self.mapping isEqualToDictionary:object.mapping];
}

- (NSUInteger)hash
{
  return (NSUInteger) self.lines ^ self.mapping.hash;
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
  BOOL lines = self.lines;
  NSArray<NSArray *> *results = [FBConcurrentCollectionOperations
    mapFilter:[searchers copy]
    map:^ NSArray * (FBDiagnosticLogSearch *search) {
      NSArray<NSString *> *matches = lines ? search.matchingLines : search.allMatches;
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

+ (NSDictionary *)searchDiagnostics:(NSArray<FBDiagnostic *> *)diagnostics withPredicate:(FBLogSearchPredicate *)predicate lines:(BOOL)lines
{
  return [[[self withMapping:@{@[] : @[predicate]} lines:lines error:nil] search:diagnostics] mapping];
}

@end
