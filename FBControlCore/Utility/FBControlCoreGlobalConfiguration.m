/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

+ (BOOL)confirmCodesignaturesAreValid
{
  return NSProcessInfo.processInfo.environment[ConfirmShimsAreSignedEnv].boolValue;
}

+ (NSString *)description
{
  return [NSString stringWithFormat:@"Default Logger %@", logger];
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
  return [FBControlCoreLogger systemLoggerWritingToStderr:self.stderrLoggingEnabledByDefault withDebugLogging:self.debugLoggingEnabledByDefault];
}

+ (BOOL)stderrLoggingEnabledByDefault
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging] boolValue];
}

+ (BOOL)debugLoggingEnabledByDefault
{
  return [NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging] boolValue];
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
