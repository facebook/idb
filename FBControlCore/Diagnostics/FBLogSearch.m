/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLogSearch.h"

#import "FBCollectionInformation.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBControlCoreError.h"
#import "FBDiagnostic.h"
#import "NSPredicate+FBControlCore.h"

static NSString *const KeySubstrings = @"substrings";
static NSString *const KeyRegex = @"regex";

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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBLogSearchPredicate_Regex alloc] initWithRegularExpression:self.regularExpression];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    KeyRegex: self.regularExpression.pattern ?: NSNull.null
  };
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

- (NSString *)description
{
  return [NSString stringWithFormat:@"Of Regex: %@", self.regularExpression.pattern];
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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBLogSearchPredicate_Substrings alloc] initWithSubstrings:self.substrings];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    KeySubstrings: self.substrings,
  };
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

- (NSString *)description
{
  return [NSString stringWithFormat:@"Of Substrings: %@", [FBCollectionInformation oneLineDescriptionFromArray:self.substrings]];
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

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a dictionary<string, id>", json] fail:error];
  }

  NSArray<NSString *> *substrings = json[KeySubstrings];
  if ([FBCollectionInformation isArrayHeterogeneous:substrings withClass:NSString.class]) {
    return [self substrings:substrings];
  }

  NSString *regexPattern = json[KeyRegex];
  if ([regexPattern isKindOfClass:NSString.class]) {
    return [self regex:regexPattern];
  }

  return [[FBControlCoreError describeFormat:@"%@ does not contain a valid predicate", json] fail:error];
}

#pragma mark Helpers

+ (nullable NSString *)logAgumentsFromPredicates:(NSArray<FBLogSearchPredicate *> *)predicates error:(NSError **)error
{
  NSMutableArray<NSString *> *tokens = [NSMutableArray array];
  for (FBLogSearchPredicate *predicate in predicates) {
    if ([predicate isKindOfClass:FBLogSearchPredicate_Substrings.class]) {
      for (NSString *substring in ((FBLogSearchPredicate_Substrings *)predicate).substrings) {
        [tokens addObject:[NSString stringWithFormat:@"eventMessage contains '%@'", substring]];
      }
      continue;
    }
    if ([predicate isKindOfClass:FBLogSearchPredicate_Regex.class]) {
      [tokens addObject:[NSString stringWithFormat:@"eventMessage MATCHES '%@'", ((FBLogSearchPredicate_Regex *) predicate).regularExpression.pattern]];
      continue;
    }
    return [[FBControlCoreError
      describeFormat:@"Could not compile %@ as a log(1) predicate", predicate]
      fail:error];
  }
  return [tokens componentsJoinedByString:@" || "];
}

#pragma mark Public API

- (NSString *)match:(NSString *)line
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
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

@end

#pragma mark - FBLogSearch

@interface FBLogSearch ()

- (NSArray<NSString *> *)matchesWithLines:(BOOL)lines;
- (instancetype)initWithPrediate:(FBLogSearchPredicate *)predicate;

@end

@interface FBLogSearch_WithStorage : FBLogSearch

@property (nonatomic, copy, readonly) NSArray<NSString *> *storedLines;

@end

@implementation FBLogSearch_WithStorage

- (instancetype)initWithStoredLines:(NSArray<NSString *> *)storedLines prediate:(FBLogSearchPredicate *)predicate
{
  self = [super initWithPrediate:predicate];
  if (!self) {
    return nil;
  }

  _storedLines = storedLines;

  return self;
}

- (NSArray<NSString *> *)lines
{
  return self.storedLines;
}

@end

@implementation FBLogSearch

#pragma mark Intitializers

+ (FBLogSearch *)withText:(NSString *)text predicate:(FBLogSearchPredicate *)predicate
{
  NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  return [[FBLogSearch_WithStorage alloc] initWithStoredLines:lines prediate:predicate];
}

- (instancetype)initWithPrediate:(FBLogSearchPredicate *)predicate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _predicate = predicate;

  return self;
}

#pragma mark Public API

- (NSArray<NSString *> *)lines
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

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

@implementation FBDiagnosticLogSearch

#pragma mark Initializers

+ (instancetype)withDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate
{
  return [[FBDiagnosticLogSearch alloc] initWithDiagnostic:diagnostic predicate:predicate];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic predicate:(FBLogSearchPredicate *)predicate
{
  self = [super initWithPrediate:predicate];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;

  return self;
}

- (NSArray<NSString *> *)lines
{
  return self.diagnostic.isSearchableAsText
    ? [self.diagnostic.asString componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
    : @[];
}

@end
