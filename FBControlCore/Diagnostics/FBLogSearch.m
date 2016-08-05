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
#import "NSPredicate+FBControlCore.h"

@interface FBLogSearch ()

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate;
- (NSArray<NSString *> *)matchesWithLines:(BOOL)lines;

@end

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
  if (!result || result.range.location == NSNotFound || result.range.length < 1) {
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
    options:NSRegularExpressionAnchorsMatchLines
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

#pragma mark - FBLogSearch

@interface FBLogSearch_Invalid : FBLogSearch

@end

@implementation FBLogSearch_Invalid

@end

@interface FBLogSearch_Linewise : FBLogSearch

@end

@implementation FBLogSearch_Linewise

#pragma mark Public API

- (NSArray<NSString *> *)matchesWithLines:(BOOL)outputLines
{
  FBLogSearchPredicate *predicate = self.predicate;

  return [FBConcurrentCollectionOperations
    mapFilter:self.lines
    map:^ NSString * (NSString *line) {
      NSString *substring = [predicate match:line];
      if (!substring) {
        return nil;
      }
      return outputLines ? line : substring;
    }
    predicate:NSPredicate.notNullPredicate];
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

- (NSArray<NSString *> *)matchesWithLines:(BOOL)lines
{
  return nil;
}

- (NSArray<NSString *> *)allMatches
{
  return [self matchesWithLines:NO];
}

- (NSArray<NSString *> *)matchingLines
{
  return [self matchesWithLines:YES];
}

- (NSString *)firstMatch
{
  return [self.allMatches firstObject];
}

- (NSString *)firstMatchingLine
{
  return [self.matchingLines firstObject];
}

@end
