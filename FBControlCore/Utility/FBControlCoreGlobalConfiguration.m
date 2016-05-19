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
#import "FBTaskExecutor.h"

NSString *const FBControlCoreStderrLogging = @"FBControlCore_LOGGING";
NSString *const FBControlCoreDebugLogging = @"FBControlCore_DEBUG_LOGGING";

static id<FBControlCoreLogger> logger;

@implementation FBControlCoreGlobalConfiguration

+ (NSString *)developerDirectory
{
  static dispatch_once_t onceToken;
  static NSString *directory;
  dispatch_once(&onceToken, ^{
    directory = [[[FBTaskExecutor.sharedInstance
      taskWithLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
      startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout]
      stdOut];
    NSCAssert(directory, @"Xcode Path could not be determined from `xcode-select`");
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

+ (NSDecimalNumber *)sdkVersionNumber
{
  return [NSDecimalNumber decimalNumberWithString:self.sdkVersion];
}

+ (NSNumberFormatter *)sdkVersionNumberFormatter
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

+ (NSString *)sdkVersion
{
  static dispatch_once_t onceToken;
  static NSString *sdkVersion;
  dispatch_once(&onceToken, ^{
    NSString *showSdks= [[[FBTaskExecutor.sharedInstance
      taskWithLaunchPath:@"/usr/bin/xcodebuild" arguments:@[@"-showsdks"]]
      startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout]
      stdOut];

    NSString *pattern = @"iphonesimulator(.*)";
    NSRegularExpression *regex = [NSRegularExpression
      regularExpressionWithPattern:pattern
      options:(NSRegularExpressionOptions) 0
      error:nil];

    NSArray *matches = [regex
      matchesInString:showSdks
      options:(NSMatchingOptions) 0
      range:NSMakeRange(0, showSdks.length)];

    // If xcode license is not accepted, no sdk is shown.
    NSCAssert(matches.count >= 1, @"Could not find a match for the SDK version");

    NSTextCheckingResult *match = [matches lastObject];
    NSCAssert(
      match.numberOfRanges == 2, @"We expect to have exactly 1 match. Text is %@",
      [showSdks substringWithRange:match.range]
    );

    sdkVersion = [showSdks substringWithRange:[match rangeAtIndex:1]];
  });
  return sdkVersion;
}

+ (NSTimeInterval)fastTimeout
{
  return 10;
}

+ (NSTimeInterval)regularTimeout
{
  return 30;
}

+ (dispatch_time_t)regularDispatchTimeout
{
  NSTimeInterval timeout = self.regularTimeout;
  int64_t timeoutInt = ((int64_t) timeout) * ((int64_t) NSEC_PER_SEC);
  return dispatch_time(DISPATCH_TIME_NOW, timeoutInt);
}

+ (NSTimeInterval)slowTimeout
{
  return 120;
}

+ (BOOL)supportsCustomDeviceSets
{
  // Prior to Xcode 7, 'iOS Simulator.app' calls `+[SimDeviceSet defaultSet]` directly
  // This means that the '-DeviceSetPath' won't do anything for Simulators booted with prior to Xcode 7.
  // It should be possible to fix this by injecting a shim that swizzles this method in these Xcode versions.
  return [self.sdkVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]];
}

+ (id<FBControlCoreLogger>)defaultLogger
{
  if (logger) {
    return logger;
  }
  logger = [self createDefaultLogger];
  return logger;
}

+ (NSString *)description
{
  return [NSString stringWithFormat:
    @"Developer Directory %@ | SDK Version %@ | Supports Custom Device Sets %d | Debug Logging Enabled %d",
    self.developerDirectory,
    self.sdkVersion,
    self.supportsCustomDeviceSets,
    self.debugLoggingEnabled
  ];
}

+ (BOOL)debugLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging] boolValue];
}


#pragma mark Private

+ (id<FBControlCoreLogger>)createDefaultLogger
{
  return [FBControlCoreLogger aslLoggerWritingToStderrr:self.stderrLoggingEnabled withDebugLogging:self.debugLoggingEnabled];
}

+ (BOOL)stderrLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging] boolValue] || self.debugLoggingEnabled;
}

@end

@implementation FBControlCoreGlobalConfiguration (Environment)

+ (void)setDefaultLogger:(id<FBControlCoreLogger>)defaultLogger
{
  if (logger) {
    [defaultLogger logFormat:@"Overriding the Default Logger with %@", defaultLogger];
  }
  logger = defaultLogger;
}

+ (void)setDefaultLoggerToASLWithStderrLogging:(BOOL)stderrLogging debugLogging:(BOOL)debugLogging
{
  setenv(FBControlCoreStderrLogging.UTF8String, stderrLogging ? "YES" : "NO", 1);
  setenv(FBControlCoreDebugLogging.UTF8String, debugLogging ? "YES" : "NO", 1);
}

@end
