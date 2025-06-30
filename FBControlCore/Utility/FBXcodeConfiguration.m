/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXcodeConfiguration.h"

#import "FBBundleDescriptor.h"
#import "FBFuture+Sync.h"
#import "FBiOSTargetConfiguration.h"
#import "FBProcessBuilder.h"
#import "FBXcodeDirectory.h"

@implementation FBXcodeConfiguration

+ (NSString *)developerDirectory
{
  return [self findXcodeDeveloperDirectoryOrAssert];
}

+ (nullable NSString *)getDeveloperDirectoryIfExists
{
  return [self findXcodeDeveloperDirectoryFromXcodeSelect:nil];
}

+ (NSString *)contentsDirectory
{
  return [[self developerDirectory] stringByDeletingLastPathComponent];
}

+ (NSDecimalNumber *)xcodeVersionNumber
{
  static dispatch_once_t onceToken;
  static NSDecimalNumber *versionNumber;
  dispatch_once(&onceToken, ^{
    NSString *versionNumberString = [FBXcodeConfiguration
      readValueForKey:@"CFBundleShortVersionString"
      fromPlistAtPath:FBXcodeConfiguration.xcodeInfoPlistPath];
    versionNumber = [NSDecimalNumber decimalNumberWithString:versionNumberString];
  });
  return versionNumber;
}

+ (NSOperatingSystemVersion)xcodeVersion
{
  static dispatch_once_t onceToken;
  static NSOperatingSystemVersion version;
  dispatch_once(&onceToken, ^{
    version = [FBOSVersion operatingSystemVersionFromName:self.xcodeVersionNumber.stringValue];
  });
  return version;
}

+ (NSString *)iosSDKVersion
{
  static dispatch_once_t onceToken;
  static NSString *sdkVersion;
  dispatch_once(&onceToken, ^{
    sdkVersion = [FBXcodeConfiguration
      readValueForKey:@"Version"
      fromPlistAtPath:FBXcodeConfiguration.iPhoneSimulatorPlatformInfoPlistPath];
  });
  return sdkVersion;
}

+ (NSDecimalNumber *)iosSDKVersionNumber
{
  return [NSDecimalNumber decimalNumberWithString:self.iosSDKVersion];
}

+ (NSNumberFormatter *)iosSDKVersionNumberFormatter
{
  static dispatch_once_t onceToken;
  static NSNumberFormatter *formatter;
  dispatch_once(&onceToken, ^{
    formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 3;
  });
  return formatter;
}

+ (BOOL)isXcode10OrGreater
{
  return [FBXcodeConfiguration.xcodeVersionNumber compare:[NSDecimalNumber decimalNumberWithString:@"10.0"]] != NSOrderedAscending;
}

+ (BOOL)isXcode12OrGreater
{
  return [FBXcodeConfiguration.xcodeVersionNumber compare:[NSDecimalNumber decimalNumberWithString:@"12.0"]] != NSOrderedAscending;
}

+ (BOOL)isXcode12_5OrGreater
{
  return [FBXcodeConfiguration.xcodeVersionNumber compare:[NSDecimalNumber decimalNumberWithString:@"12.5"]] != NSOrderedAscending;
}

+ (FBBundleDescriptor *)simulatorApp
{
  NSError *error = nil;
  FBBundleDescriptor *application = [FBBundleDescriptor bundleFromPath:self.simulatorApplicationPath error:&error];
  NSAssert(application, @"Expected to be able to build an Application, got an error %@", application);
  return application;
}

+ (NSString *)description
{
  return [NSString stringWithFormat:
    @"Developer Directory %@ | Xcode Version %@ | iOS SDK Version %@",
    self.developerDirectory,
    self.xcodeVersionNumber,
    self.iosSDKVersionNumber
  ];
}

- (NSString *)description
{
  return [FBXcodeConfiguration description];
}

#pragma mark Private

+ (NSString *)simulatorApplicationPath
{
  NSString *simulatorBinaryName =  @"Simulator";
  return [[self.developerDirectory
    stringByAppendingPathComponent:@"Applications"]
    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.app", simulatorBinaryName]];
}

+ (NSString *)iPhoneSimulatorPlatformInfoPlistPath
{
  return [[self.developerDirectory
    stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform"]
    stringByAppendingPathComponent:@"Info.plist"];
}

+ (NSString *)xcodeInfoPlistPath
{
  return [[self.developerDirectory
    stringByDeletingLastPathComponent]
    stringByAppendingPathComponent:@"Info.plist"];
}

+ (NSString *)findXcodeDeveloperDirectoryOrAssert
{
  NSError *error = nil;
  NSString *directory = [self findXcodeDeveloperDirectoryFromXcodeSelect:&error];
  NSAssert(directory, @"Failed to get developer directory from xcode-select: %@", error.description);
  return directory;
}

+ (nullable NSString *)findXcodeDeveloperDirectoryFromXcodeSelect:(NSError **)error
{
  static dispatch_once_t onceToken;
  static NSString *directory;
  static NSError *savedError;
  dispatch_once(&onceToken, ^{
    NSError *innerError = nil;
    directory = [FBXcodeDirectory.xcodeSelectDeveloperDirectory await:&innerError];
    savedError = innerError;
  });
  if (error) {
    *error = savedError;
  }
  return directory;
}

+ (nullable id)readValueForKey:(NSString *)key fromPlistAtPath:(NSString *)plistPath
{
  NSAssert([NSFileManager.defaultManager fileExistsAtPath:plistPath], @"plist does not exist at path '%@'", plistPath);
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
  NSAssert(infoPlist, @"Could not read plist at '%@'", plistPath);
  id value = infoPlist[key];
  NSAssert(value, @"'%@' does not exist in plist '%@'", key, infoPlist.allKeys);
  return value;
}

@end
