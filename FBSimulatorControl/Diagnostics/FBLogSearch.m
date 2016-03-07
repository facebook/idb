/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogSearch.h"

#import "FBDiagnostic.h"
#import "FBCollectionInformation.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBSimulatorError.h"

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

- (BOOL)matchesLine:(NSString *)line
{
  if (!self.regularExpression) {
    return NO;
  }
  NSRange range = line.length ? NSMakeRange(0, line.length - 1) : NSMakeRange(0, 0);
  return [self.regularExpression numberOfMatchesInString:line options:0 range:range] > 0;
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

- (BOOL)matchesLine:(NSString *)line
{
  for (NSString *needle in self.substrings) {
    if ([line rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    return YES;
  }
  return NO;
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

  return [[FBSimulatorError describeFormat:@"%@ does not contain a valid predicate", json] fail:error];
}

#pragma mark Public API

- (BOOL)matchesLine:(NSString *)line
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
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

@interface FBLogSearch ()

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate;

@end

@interface FBLogSearch_Invalid : FBLogSearch

@end

@implementation FBLogSearch_Invalid

@end

@interface FBLogSearch_Linewise : FBLogSearch

@property (nonatomic, copy, readonly) NSArray *lines;

@end

@implementation FBLogSearch_Linewise

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate lines:(NSArray *)lines
{
  self = [super initWithDiagnostic:diagnostic predicate:predicate];
  if (!self) {
    return nil;
  }

  _lines = lines;

  return self;
}

- (NSString *)firstMatchingLine
{
  FBLogSearchPredicate *logSearchPredicate = self.predicate;
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *line, NSDictionary *_) {
    return [logSearchPredicate matchesLine:line];
  }];

  return [[FBConcurrentCollectionOperations
    filter:self.lines predicate:predicate]
    firstObject];
}

@end

@implementation FBLogSearch

#pragma mark Initializers

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate
{
  if (!diagnostic.isSearchableAsText) {
    return [FBLogSearch_Invalid new];
  }
  NSArray *lines = [diagnostic.asString componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  return [[FBLogSearch_Linewise alloc] initWithDiagnostic:diagnostic predicate:predicate lines:lines];
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

- (NSString *)firstMatchingLine
{
  return nil;
}

@end
