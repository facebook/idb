//
//  FBXCTestKeyboardSimulatorConfigurator.m
//  FBXCTestKit
//
//  Created by Алексеев Владислав on 27.03.2018.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "FBXCTestKeyboardSimulatorConfigurator.h"
#import <FBSimulatorControl/FBSimulatorControl.h>

NSErrorDomain const FBXCTestKeyboardSimulatorConfiguratorErrorDomain = @"FBXCTestKeyboardSimulatorConfiguratorErrorDomain";
const NSInteger FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingLocalizationSettings = 1;
const NSInteger FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingAlertSettings = 2;

@interface FBXCTestKeyboardSimulatorConfigurator()

@property (nonatomic, copy, readonly) NSLocale *locale;
@property (nonatomic, copy, readonly) NSArray<NSString *> *keyboards;
@property (nonatomic, copy, readonly) NSArray<NSString *> *passcodeKeyboards;
@property (nonatomic, copy, readonly) NSArray<NSString *> *languages;
@property (nonatomic, copy, readonly) NSNumber *addingEmojiKeybordHandled;
@property (nonatomic, copy, readonly) NSNumber *enableKeyboardExpansion;
@property (nonatomic, copy, readonly) NSNumber *didShowInternationalInfoAlert;
@property (nonatomic, weak, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestKeyboardSimulatorConfigurator

+ (instancetype)configurationFromDictionary:(NSDictionary *)dictionary logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithLocaleIdentifier:dictionary[@"locale_identifier"]
                                      keyboards:dictionary[@"keyboards"]
                              passcodeKeyboards:dictionary[@"passcode_keyboards"]
                                      languages:dictionary[@"languages"]
                      addingEmojiKeybordHandled:dictionary[@"adding_emoji_keybord_handled"]
                        enableKeyboardExpansion:dictionary[@"enable_keyboard_expansion"]
                  didShowInternationalInfoAlert:dictionary[@"did_show_international_info_alert"]
                                         logger:logger];
}

- (instancetype)initWithLocaleIdentifier:(NSString *)localeIdentifier
                               keyboards:(NSArray<NSString *> *)keyboards
                       passcodeKeyboards:(NSArray<NSString *> *)passcodeKeyboards
                               languages:(NSArray<NSString *> *)languages
               addingEmojiKeybordHandled:(NSNumber *)addingEmojiKeybordHandled
                 enableKeyboardExpansion:(NSNumber *)enableKeyboardExpansion
           didShowInternationalInfoAlert:(NSNumber *)didShowInternationalInfoAlert
                                  logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _locale = [NSLocale localeWithLocaleIdentifier:localeIdentifier ?: @"en_US"];
  _keyboards = [NSArray arrayWithArray:keyboards ?: @[@"en_US@sw=QWERTY;hw=Automatic"]];
  _passcodeKeyboards = [NSArray arrayWithArray:passcodeKeyboards ?: @[@"en_US@sw=QWERTY;hw=Automatic"]];
  _languages = [NSArray arrayWithArray:languages ?: @[@"en"]];
  _addingEmojiKeybordHandled = [addingEmojiKeybordHandled ?: @YES copy];
  _enableKeyboardExpansion = [enableKeyboardExpansion ?: @YES copy];
  _didShowInternationalInfoAlert = [didShowInternationalInfoAlert ?: @YES copy];
  _logger = logger;
  return self;
}

- (FBFuture *)configureSimulator:(FBSimulator *)simulator
{
  return [FBFuture futureWithFutures:
  @[
    [self patchLocalizationSettingsForSimulator:simulator],
    [self patchKeyboardInternationalInfoAlertForSimulator:simulator]
    ]];
}

#pragma mark - Private

- (BOOL)loadPlistFromPath:(NSString *)pathInDataFolder fromSimulator:(FBSimulator *)simulator outContents:(out NSDictionary **)outContents outFormat:(out NSPropertyListFormat *)outFormat error:(NSError **)error
{
  NSString *plistPath = [simulator.dataDirectory stringByAppendingPathComponent:pathInDataFolder];
  NSData *plistData = [NSData dataWithContentsOfFile:plistPath options:0 error:error];
  if (plistData == nil || *error != nil) { return NO; }
  
  NSDictionary *immutableContents = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:outFormat error:error];
  if (![immutableContents isKindOfClass:NSDictionary.class] || *error != nil) { return NO; }
  
  *outContents = immutableContents;
  return YES;
}

- (BOOL)writePlistContents:(NSDictionary *)plistContents toPath:(NSString *)pathInDataFolder format:(NSPropertyListFormat)format inSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSString *plistPath = [simulator.dataDirectory stringByAppendingPathComponent:pathInDataFolder];
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plistContents format:format options:0 error:error];
  if (plistData == nil || *error != nil) { return NO; }
  if (![plistData writeToFile:plistPath options:NSDataWritingAtomic error:error]) { return NO; }
  
  return YES;
}

- (FBFuture *)patchLocalizationSettingsForSimulator:(FBSimulator *)simulator
{
  static NSString *kGlobalPreferencesPlist = @"Library/Preferences/.GlobalPreferences.plist";
  NSError *error = nil;
  
  NSDictionary *immutableContents = nil;
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  if (![self loadPlistFromPath:kGlobalPreferencesPlist fromSimulator:simulator outContents:&immutableContents outFormat:&format error:&error]) {
    return [FBFuture futureWithError:
            [[[[FBControlCoreError describeFormat:@"Error reading current localization settings from file: %@", error]
               inDomain:FBXCTestKeyboardSimulatorConfiguratorErrorDomain]
              code:FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingLocalizationSettings]
             build]];
  }
  
  FBLocalizationOverride *keyboardOverrides = [FBLocalizationOverride withLocale:self.locale
                                                                       keyboards:self.keyboards
                                                               passcodeKeyboards:self.passcodeKeyboards
                                                                       languages:self.languages
                                                       addingEmojiKeybordHandled:self.addingEmojiKeybordHandled.boolValue
                                                         enableKeyboardExpansion:self.enableKeyboardExpansion.boolValue];
  NSDictionary *updatedValues = keyboardOverrides.defaultsDictionary;
  
  NSMutableDictionary *plistContents = [NSMutableDictionary dictionaryWithDictionary:immutableContents];
  [plistContents removeObjectsForKeys:updatedValues.allKeys];
  [plistContents addEntriesFromDictionary:updatedValues];
  
  [self.logger.debug logFormat:@"Writing keyboard settings to to %@: %@", kGlobalPreferencesPlist, plistContents];
  
  if ([self writePlistContents:plistContents toPath:kGlobalPreferencesPlist format:format inSimulator:simulator error:&error]) {
    return [FBFuture futureWithResult:NSNull.null];
  } else {
    return [FBFuture futureWithError:
            [[[[FBControlCoreError describeFormat:@"Error updating localization settings: %@", error]
               inDomain:FBXCTestKeyboardSimulatorConfiguratorErrorDomain]
              code:FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingLocalizationSettings]
             build]];
  }
}

- (FBFuture *)patchKeyboardInternationalInfoAlertForSimulator:(FBSimulator *)simulator
{
  static NSString *kApplePreferencesPlist = @"Library/Preferences/com.apple.Preferences.plist";
  
  NSDictionary *immutableContents = nil;
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  NSError *error = nil;
  if ([NSFileManager.defaultManager fileExistsAtPath:[simulator.dataDirectory stringByAppendingPathComponent:kApplePreferencesPlist]]) {
    if (![self loadPlistFromPath:kApplePreferencesPlist fromSimulator:simulator outContents:&immutableContents outFormat:&format error:&error]) {
      return [FBFuture futureWithError:
              [[[[FBControlCoreError describeFormat:@"Error reading international info alert setting from file: %@", error]
                 inDomain:FBXCTestKeyboardSimulatorConfiguratorErrorDomain]
                code:FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingAlertSettings]
               build]];
    }
  }

  NSMutableDictionary *plistContents = [NSMutableDictionary dictionaryWithDictionary:immutableContents];
  [plistContents setObject:self.didShowInternationalInfoAlert ? @"true" : @"false"
                    forKey:@"UIKeyboardDidShowInternationalInfoAlert"];
  
  [self.logger.debug logFormat:@"Writing keyboard settings to to %@: %@", kApplePreferencesPlist, plistContents];
  
  if ([self writePlistContents:plistContents toPath:kApplePreferencesPlist format:format inSimulator:simulator error:&error] || error != nil) {
    return [FBFuture futureWithResult:NSNull.null];
  } else {
    return [FBFuture futureWithError:
            [[[[FBControlCoreError describeFormat:@"Error updating international info alert setting: %@", error]
               inDomain:FBXCTestKeyboardSimulatorConfiguratorErrorDomain]
              code:FBXCTestKeyboardSimulatorConfiguratorErrorUpdatingAlertSettings]
             build]];
  }
}

@end
