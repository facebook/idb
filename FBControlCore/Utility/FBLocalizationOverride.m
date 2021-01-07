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

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Object is immutable.
  return self;
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

#pragma mark Private

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
