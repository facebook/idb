// Copyright 2004-present Facebook. All Rights Reserved.

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogSearch.h"

#import "FBCollectionInformation.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBControlCoreError.h"
#import "FBDiagnostic.h"

#pragma mark - FBLogSearchPredicate

@interface FBLogSearchPredicate_Regex : FBLogSearchPredicate

@property (nonatomic, copy, readonly) NSRegularExpression *regularExpression;

@end

@implementation FBLogSearchPredicate_Regex

- (instancetype)initWithRegularExpression:(NSRegularExpression *)regularExpression
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _regularExpression = regularExpression;

  return self;
}

- (NSString *)match:(NSString *)line
{
  if (!self.regularExpression) {
    return nil;
  }
  NSRange range = line.length ? NSMakeRange(0, line.length - 1) : NSMakeRange(0, 0);
  NSTextCheckingResult *result = [self.regularExpression firstMatchInString:line options:0 range:range];
  if (result.range.location == NSNotFound) {
    return nil;
  }
  return [line substringWithRange:result.range];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _regularExpression = [coder decodeObjectForKey:NSStringFromSelector(@selector(regularExpression))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.regularExpression forKey:NSStringFromSelector(@selector(regularExpression))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBLogSearchPredicate_Regex alloc] initWithRegularExpression:self.regularExpression];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"regex" : self.regularExpression.pattern ?: NSNull.null
  };
}

#pragma mark FBDebugDescribeable Implementation

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Of Regex: %@", self.regularExpression.pattern];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBLogSearchPredicate_Regex *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.regularExpression isEqual:object.regularExpression];
}

- (NSUInteger)hash
{
  return self.regularExpression.hash;
}

@end

@interface FBLogSearchPredicate_Substrings : FBLogSearchPredicate

@property (nonatomic, copy, readonly) NSArray *substrings;

@end

@implementation FBLogSearchPredicate_Substrings

- (instancetype)initWithSubstrings:(NSArray *)substrings
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _substrings = substrings;

  return self;
}

- (NSString *)match:(NSString *)line
{
  for (NSString *needle in self.substrings) {
    if ([line rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    return needle;
  }
  return nil;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _substrings = [coder decodeObjectForKey:NSStringFromSelector(@selector(substrings))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.substrings forKey:NSStringFromSelector(@selector(substrings))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBLogSearchPredicate_Substrings alloc] initWithSubstrings:self.substrings];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"substrings" : self.substrings,
  };
}

#pragma mark FBDebugDescribeable Implementation

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Of Substrings: %@", [FBCollectionInformation oneLineDescriptionFromArray:self.substrings]];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBLogSearchPredicate_Substrings *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }

  return [self.substrings isEqualToArray:object.substrings];
}

- (NSUInteger)hash
{
  return self.substrings.hash;
}

@end

@implementation FBLogSearchPredicate

#pragma mark Initializers

+ (instancetype)substrings:(NSArray *)substrings
{
  return [[FBLogSearchPredicate_Substrings alloc] initWithSubstrings:substrings];
}

+ (instancetype)regex:(NSString *)pattern
{
  NSRegularExpression *regex = [NSRegularExpression
    regularExpressionWithPattern:pattern
    options:0
    error:nil];
  return [[FBLogSearchPredicate_Regex alloc] initWithRegularExpression:regex];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSArray *substrings = json[@"substrings"];
  if ([FBCollectionInformation isArrayHeterogeneous:substrings withClass:NSString.class]) {
    return [self substrings:substrings];
  }

  NSString *regexPattern = json[@"regex"];
  if ([regexPattern isKindOfClass:NSString.class]) {
    return [self regex:regexPattern];
  }

  return [[FBControlCoreError describeFormat:@"%@ does not contain a valid predicate", json] fail:error];
}

#pragma mark Public API

- (NSString *)match:(NSString *)line
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBDebugDescribeable Implementation

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

#pragma mark - FBBatchLogSearch

@interface FBBatchLogSearch ()

@property (nonatomic, copy, readonly) NSDictionary *mapping;

@end

@implementation FBBatchLogSearch

#pragma mark Initializers

+ (instancetype)withMapping:(NSDictionary *)mapping error:(NSError **)error
{
  for (id key in mapping.allKeys) {
    if (![key isKindOfClass:NSArray.class]) {
      return [[FBControlCoreError describeFormat:@"%@ key is not an array", key] fail:error];
    }
    if (![FBCollectionInformation isArrayHeterogeneous:key withClass:NSString.class]) {
      return [[FBControlCoreError describeFormat:@"%@ key is not an array of strings", key] fail:error];
    }
  }
  for (id value in mapping.allValues) {
    if (![value isKindOfClass:NSArray.class]) {
      return [[FBControlCoreError describeFormat:@"%@ value is not an array", value] fail:error];
    }
    if (![FBCollectionInformation isArrayHeterogeneous:value withClass:FBLogSearchPredicate.class]) {
      return [[FBControlCoreError describeFormat:@"%@ value is not an array of log search predicates", value] fail:error];
    }
  }
  return [[FBBatchLogSearch alloc] initWithMapping:mapping];
}

+ (instancetype)inflateFromJSON:(NSDictionary *)json error:(NSError **)error
{
  if (![json isKindOfClass:NSDictionary.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary", json] fail:error];
  }
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSArray.class valueClass:NSArray.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary of <array, array>", json] fail:error];
  }

  NSMutableDictionary *mapping = [NSMutableDictionary dictionary];
  for (NSString *key in json.allKeys) {
    NSMutableArray *predicates = [NSMutableArray array];
    for (NSDictionary *predicateJSON in json[key]) {
      FBLogSearchPredicate *predicate = [FBLogSearchPredicate inflateFromJSON:predicateJSON error:error];
      if (!predicate) {
        return [[FBControlCoreError describeFormat:@"%@ is not a predicate", predicateJSON] fail:error];
      }
      [predicates addObject:predicate];
    }

    mapping[key] = [predicates copy];
  }
  return [self withMapping:[mapping copy] error:error];
}

- (instancetype)initWithMapping:(NSDictionary *)mapping
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mapping = mapping;

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

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.mapping forKey:NSStringFromSelector(@selector(mapping))];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBBatchLogSearch alloc] initWithMapping:self.mapping];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  for (NSArray *key in self.mapping) {
    dictionary[key] = [self.mapping[key] valueForKey:@"jsonSerializableRepresentation"];
  }
  return [dictionary copy];
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

  return [self.mapping isEqualToDictionary:object.mapping];
}

- (NSUInteger)hash
{
  return self.mapping.hash;
}

#pragma mark Public API

- (NSDictionary *)search:(NSArray *)diagnostics
{
  NSParameterAssert([FBCollectionInformation isArrayHeterogeneous:diagnostics withClass:FBDiagnostic.class]);

  // Construct an NSDictionary<NSString, FBDiagnostic> of diagnostics.
  NSDictionary *namesToDiagnostics = [NSDictionary dictionaryWithObjects:diagnostics forKeys:[diagnostics valueForKey:@"shortName"]];

  // Construct and NSArray<FBLogSearch> instances
  NSMutableArray *searchers = [NSMutableArray array];
  for (NSArray *nameArray in self.mapping.allKeys) {
    NSArray *predicates = self.mapping[nameArray];

    if ([nameArray isEqualToArray:@[]]) {
      for (FBDiagnostic *diagnostic in diagnostics) {
        for (FBLogSearchPredicate *predicate in predicates) {
          [searchers addObject:[FBLogSearch withDiagnostic:diagnostic predicate:predicate]];
        }
      }
    }
    for (NSString *name in nameArray) {
      FBDiagnostic *diagnostic = namesToDiagnostics[name];
      if (!diagnostic) {
        continue;
      }
      for (FBLogSearchPredicate *predicate in predicates) {
        [searchers addObject:[FBLogSearch withDiagnostic:diagnostic predicate:predicate]];
      }
    }
  }

  // Perform the search, concurrently
  NSArray *results = [FBConcurrentCollectionOperations
    mapFilter:[searchers copy]
    map:^ NSArray * (FBLogSearch *searcher) {
      NSString *line = searcher.firstMatchingLine;
      if (!line) {
        return nil;
      }
      return @[searcher.diagnostic.shortName, line];
    }
    predicate:FBConcurrentCollectionOperations.notNullPredicate];

  // Rebuild the output dictionary
  NSMutableDictionary *output = [NSMutableDictionary dictionary];
  for (NSArray *result in results) {
    NSString *key = result[0];
    NSString *value = result[1];
    NSMutableArray *matches = output[key];
    if (!matches) {
      matches = [NSMutableArray array];
      output[key] = matches;
    }
    [matches addObject:value];
  }

  return [output copy];
}

+ (NSDictionary *)searchDiagnostics:(NSArray *)diagnostics withPredicate:(FBLogSearchPredicate *)predicate
{
  return [[self withMapping:@{@[] : @[predicate]} error:nil] search:diagnostics];
}

@end

#pragma mark - FBLogSearch

@interface FBLogSearch ()

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate;

@end

@interface FBLogSearch_Invalid : FBLogSearch

@end

@implementation FBLogSearch_Invalid

@end

@interface FBLogSearch_Linewise : FBLogSearch

@end

@implementation FBLogSearch_Linewise

#pragma mark Public API

- (NSString *)firstMatch
{
  FBLogSearchPredicate *predicate = self.predicate;

  return [[FBConcurrentCollectionOperations
    mapFilter:self.lines
    map:^ NSString * (NSString *line) {
      return [predicate match:line];
    }
    predicate:FBConcurrentCollectionOperations.notNullPredicate]
    firstObject];
}

- (NSString *)firstMatchingLine
{
  FBLogSearchPredicate *logSearchPredicate = self.predicate;
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *line, NSDictionary *_) {
    return [logSearchPredicate match:line] != nil;
  }];

  return [[FBConcurrentCollectionOperations
    filter:self.lines predicate:predicate]
    firstObject];
}

#pragma mark Private

- (NSArray *)lines
{
  return [self.diagnostic.asString componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
}

@end

@implementation FBLogSearch

#pragma mark Initializers

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate
{
  if (!diagnostic.isSearchableAsText) {
    return [FBLogSearch_Invalid new];
  }
  return [[FBLogSearch_Linewise alloc] initWithDiagnostic:diagnostic predicate:predicate];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;
  _predicate = predicate;

  return self;
}

#pragma mark Public API

- (NSString *)firstMatch
{
  return nil;
}

- (NSString *)firstMatchingLine
{
  return nil;
}

@end
