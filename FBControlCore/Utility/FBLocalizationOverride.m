/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLocalizationOverride.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"

static NSString *const LocaleKey = @"AppleLocale";
static NSString *const LanguagesKey = @"AppleLanguages";
static NSString *const KeyboardsKey = @"AppleKeyboards";
static NSString *const KeyboardsExpandedKey = @"AppleKeyboardsExpanded";

@interface FBLocalizationOverride ()

@property (nonatomic, copy, readonly) NSLocale *locale;
@property (nonatomic, copy, readonly) NSArray<NSString *> *keyboards;
@property (nonatomic, assign, readonly) BOOL enableKeyboardExpansion;

@end

@implementation FBLocalizationOverride

#pragma mark Initializers

+ (instancetype)withLocale:(NSLocale *)locale
{
  return [[FBLocalizationOverride alloc] initWithLocale:locale keyboards:@[ @"en_US@hw=US;sw=QWERTY" ] enableKeyboardExpansion:YES];
}

- (instancetype)initWithLocale:(NSLocale *)locale keyboards:(NSArray<NSString *> *)keyboards enableKeyboardExpansion:(BOOL)enableKeyboardExpansion
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _locale = locale;
  _keyboards = keyboards;
  _enableKeyboardExpansion = enableKeyboardExpansion;

  return self;
}

#pragma mark FBJSONConversion

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not an Dictionary<String, Object>", json]
      fail:error];
  }
  NSString *localeIdentifier = json[@"locale_identifier"];
  if (![localeIdentifier isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"locale_identifier %@ should be an String but isn't", localeIdentifier]
      fail:error];
  }
  NSLocale *locale = [NSLocale localeWithLocaleIdentifier:localeIdentifier];
  NSArray<NSString *> *keyboards = json[@"keyboards"];
  if (![FBCollectionInformation isArrayHeterogeneous:keyboards withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"keyboards %@ should be an Array<String> but isn't", keyboards]
      fail:error];
  }
  NSNumber *enableKeyboardExpansion = json[@"enable_keyboard_expansion"] ?: @YES;
  if (![enableKeyboardExpansion isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"enable_keyboard_expansion %@ should be an Number but isn't", enableKeyboardExpansion]
      fail:error];
  }
  return [[FBLocalizationOverride alloc] initWithLocale:locale keyboards:keyboards enableKeyboardExpansion:enableKeyboardExpansion.boolValue];
}

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"locale_identifier" : self.localeIdentifier,
    @"keyboards" : self.keyboards,
    @"enable_keyboard_expansion" : @(self.enableKeyboardExpansion)
  };
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBLocalizationOverride alloc] initWithLocale:self.locale keyboards:self.keyboards enableKeyboardExpansion:self.enableKeyboardExpansion];
}

#pragma mark Properties

- (NSDictionary<NSString *, id> *)defaultsDictionary
{
  return @{
    LocaleKey : self.localeIdentifier,
    LanguagesKey : @[ self.languageIdentifier ],
    KeyboardsKey : self.keyboards,
    KeyboardsExpandedKey : self.enableKeyboardExpansion ? @1 : @0
  };
}

- (NSArray<NSString *> *)arguments
{
  return @[
    [NSString stringWithFormat:@"-%@", LocaleKey], self.localeIdentifier,
    [NSString stringWithFormat:@"-%@", LanguagesKey], [NSString stringWithFormat:@"(%@)", self.languageIdentifier],
  ];
}

- (NSString *)localeIdentifier
{
  return self.locale.localeIdentifier;
}

- (NSString *)languageIdentifier
{
  return [self.locale objectForKey:NSLocaleLanguageCode];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Localization Override %@ | Language %@ | Keyboards %@",
    self.localeIdentifier,
    self.languageIdentifier,
    [FBCollectionInformation oneLineDescriptionFromArray:self.keyboards]
  ];
}

- (BOOL)isEqual:(FBLocalizationOverride *)override
{
  if (![override isKindOfClass:self.class]) {
    return NO;
  }

  return [self.locale isEqual:override.locale] &&
         [self.keyboards isEqualToArray:override.keyboards] &&
         self.enableKeyboardExpansion == override.enableKeyboardExpansion;
}

- (NSUInteger)hash
{
  return self.locale.hash ^ self.keyboards.hash ^ (NSUInteger) self.enableKeyboardExpansion;
}

@end
