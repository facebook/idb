/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreGlobalConfiguration.h"

#import <Foundation/Foundation.h>

#import "FBControlCoreLogger.h"

NSString *const FBControlCoreStderrLogging = @"FBCONTROLCORE_LOGGING";
NSString *const FBControlCoreDebugLogging = @"FBCONTROLCORE_DEBUG_LOGGING";
NSString *const ConfirmShimsAreSignedEnv = @"FBCONTROLCORE_CONFIRM_SIGNED_SHIMS";

static id<FBControlCoreLogger> logger;

@implementation FBControlCoreGlobalConfiguration

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
    [defaultLogger.debug logFormat:@"Overriding the Default Logger with %@", defaultLogger];
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

+ (BOOL)confirmCodesignaturesAreValid
{
  return NSProcessInfo.processInfo.environment[ConfirmShimsAreSignedEnv].boolValue;
}

+ (NSString *)description
{
  return [NSString stringWithFormat:
    @"Debug Logging Enabled %d",
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
  return @{};
}

#pragma mark Private

+ (id<FBControlCoreLogger>)createDefaultLogger
{
  return [FBControlCoreLogger systemLoggerWritingToStderr:self.stderrLoggingEnabled withDebugLogging:self.debugLoggingEnabled];
}

+ (BOOL)stderrLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging] boolValue] || self.debugLoggingEnabled;
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
