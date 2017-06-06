/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreGlobalConfiguration.h"

#import <Cocoa/Cocoa.h>

#import "FBControlCoreLogger.h"
#import "FBTaskBuilder.h"

NSString *const FBControlCoreStderrLogging = @"FBCONTROLCORE_LOGGING";
NSString *const FBControlCoreDebugLogging = @"FBCONTROLCORE_DEBUG_LOGGING";

static id<FBControlCoreLogger> logger;

@implementation FBControlCoreGlobalConfiguration

+ (NSString *)developerDirectory
{
  static dispatch_once_t onceToken;
  static NSString *directory;
  dispatch_once(&onceToken, ^{
    directory = [self findXcodeDeveloperDirectoryOrAssert];
  });
  return directory;
}

+ (nullable NSString *)appleConfiguratorApplicationPath
{
  static dispatch_once_t onceToken;
  static NSString *path = nil;
  dispatch_once(&onceToken, ^{
    path = [NSWorkspace.sharedWorkspace absolutePathForAppBundleWithIdentifier:@"com.apple.configurator.ui"];
  });
  return path;
}

+ (NSDecimalNumber *)xcodeVersionNumber
{
  static dispatch_once_t onceToken;
  static NSDecimalNumber *versionNumber;
  dispatch_once(&onceToken, ^{
    NSString *versionNumberString = [FBControlCoreGlobalConfiguration
      readValueForKey:@"CFBundleShortVersionString"
      fromPlistAtPath:FBControlCoreGlobalConfiguration.xcodeInfoPlistPath];
    versionNumber = [NSDecimalNumber decimalNumberWithString:versionNumberString];
  });
  return versionNumber;
}

+ (NSString *)iosSDKVersion
{
  static dispatch_once_t onceToken;
  static NSString *sdkVersion;
  dispatch_once(&onceToken, ^{
    sdkVersion = [FBControlCoreGlobalConfiguration
      readValueForKey:@"Version"
      fromPlistAtPath:FBControlCoreGlobalConfiguration.iPhoneSimulatorPlatformInfoPlistPath];
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

+ (NSTimeInterval)fastTimeout
{
  return 10;
}

+ (NSTimeInterval)regularTimeout
{
  return 30;
}

+ (NSTimeInterval)slowTimeout
{
  return 120;
}

+ (BOOL)isXcode7OrGreater
{
  return [FBControlCoreGlobalConfiguration.xcodeVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"7.0"]];
}

+ (BOOL)isXcode8OrGreater
{
  return [FBControlCoreGlobalConfiguration.xcodeVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"8.0"]];
}

+ (BOOL)isXcode9OrGreater
{
  return [FBControlCoreGlobalConfiguration.xcodeVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]];
}

+ (BOOL)supportsCustomDeviceSets
{
  // Prior to Xcode 7, 'iOS Simulator.app' calls `+[SimDeviceSet defaultSet]` directly
  // This means that the '-DeviceSetPath' won't do anything for Simulators booted with prior to Xcode 7.
  // It should be possible to fix this by injecting a shim that swizzles this method in these Xcode versions.
  return self.isXcode7OrGreater;
}

+ (id<FBControlCoreLogger>)defaultLogger
{
  if (logger) {
    return logger;
  }
  logger = [self createDefaultLogger];
  return logger;
}

+ (void)setDefaultLogger:(id<FBControlCoreLogger>)defaultLogger
{
  if (logger) {
    [defaultLogger logFormat:@"Overriding the Default Logger with %@", defaultLogger];
  }
  logger = defaultLogger;
}

+ (BOOL)debugLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging] boolValue];
}

+ (void)setDebugLoggingEnabled:(BOOL)enabled
{
  setenv(FBControlCoreDebugLogging.UTF8String, enabled ? "YES" : "NO", 1);
}

+ (NSString *)description
{
  return [NSString stringWithFormat:
    @"Developer Directory %@ | Xcode Version %@ | iOS SDK Version %@ | Supports Custom Device Sets %d | Debug Logging Enabled %d",
    self.developerDirectory,
    self.xcodeVersionNumber,
    self.iosSDKVersionNumber,
    self.supportsCustomDeviceSets,
    self.debugLoggingEnabled
  ];
}

- (NSString *)description
{
  return [FBControlCoreGlobalConfiguration description];
}

#pragma mark FBJSONConversion

- (id)jsonSerializableRepresentation
{
  return @{
     @"developer_directory" : FBControlCoreGlobalConfiguration.developerDirectory,
     @"xcode_version" : FBControlCoreGlobalConfiguration.xcodeVersionNumber,
     @"ios_sdk_version" : FBControlCoreGlobalConfiguration.iosSDKVersionNumber,
  };
}

#pragma mark Private

+ (id<FBControlCoreLogger>)createDefaultLogger
{
  return [FBControlCoreLogger systemLoggerWritingToStderrr:self.stderrLoggingEnabled withDebugLogging:self.debugLoggingEnabled];
}

+ (BOOL)stderrLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging] boolValue] || self.debugLoggingEnabled;
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
  FBTask *task = [[FBTaskBuilder
    taskWithLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout];
  NSString *directory = [task stdOut];
  NSAssert(directory, @"Xcode Path could not be determined from `xcode-select`: %@", task.error);
  directory = [directory stringByResolvingSymlinksInPath];
  NSAssert([NSFileManager.defaultManager fileExistsAtPath:directory], @"No Xcode Directory at: %@", directory);
  return directory;
}

+ (nullable id)readValueForKey:(NSString *)key fromPlistAtPath:(NSString *)plistPath
{
  NSCAssert([NSFileManager.defaultManager fileExistsAtPath:plistPath], @"plist does not exist at path '%@'", plistPath);
  NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
  NSCAssert(infoPlist, @"Could not read plist at '%@'", plistPath);
  id value = infoPlist[key];
  NSCAssert(value, @"'%@' does not exist in plist '%@'", key, infoPlist.allKeys);
  return value;
}

@end

@implementation FBControlCoreGlobalConfiguration (Setters)

+ (void)setDefaultLoggerToASLWithStderrLogging:(BOOL)stderrLogging debugLogging:(BOOL)debugLogging
{
  setenv(FBControlCoreStderrLogging.UTF8String, stderrLogging ? "YES" : "NO", 1);
  [self setDebugLoggingEnabled:debugLogging];
}

@end
