/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogger.h"

#import <asl.h>

@interface FBSimulatorLogger_NSLog : NSObject <FBSimulatorLogger>

@property (nonatomic, strong, readonly) NSDateFormatter *dateFormatter;

- (NSString *)logLevelString;

@end

@interface FBSimulatorLogger_NSLog_Debug : FBSimulatorLogger_NSLog

@end

@interface FBSimulatorLogger_NSLog_Info : FBSimulatorLogger_NSLog

@end

@interface FBSimulatorLogger_NSLog_Error : FBSimulatorLogger_NSLog

@end

@implementation FBSimulatorLogger_NSLog_Debug

- (NSString *)logLevelString
{
  return @"debug";
}

@end

@implementation FBSimulatorLogger_NSLog_Error

- (NSString *)logLevelString
{
  return @"error";
}

@end

@implementation FBSimulatorLogger_NSLog_Info

- (NSString *)logLevelString
{
  return @"info";
}

@end

@implementation FBSimulatorLogger_NSLog

- (instancetype)initWithDateFormatter:(NSDateFormatter *)dateFormatter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dateFormatter = dateFormatter;

  return self;
}

#pragma mark Public

- (instancetype)log:(NSString *)string
{
  NSString *prefix = self.prefix;
  if (prefix) {
    NSLog(@"%@ %@", prefix, string);
    return self;
  }

  NSLog(@"%@", string);
  return self;
}

- (instancetype)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBSimulatorLogger>)info
{
  return [[FBSimulatorLogger_NSLog_Info alloc] initWithDateFormatter:self.dateFormatter];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_NSLog_Debug alloc] initWithDateFormatter:self.dateFormatter];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_NSLog_Error alloc] initWithDateFormatter:self.dateFormatter];
}

- (id<FBSimulatorLogger>)timestamped
{
  NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
  dateFormatter.timeStyle = NSDateFormatterMediumStyle;
  dateFormatter.dateStyle = NSDateFormatterNoStyle;
  return [[self.class alloc] initWithDateFormatter:dateFormatter];
}

#pragma mark Private

- (NSString *)prefix
{
  NSString *prefix = [self logLevelString];
  prefix = prefix ? [NSString stringWithFormat:@"[%@]", prefix] : nil;
  if (!self.dateFormatter) {
    return prefix;
  }
  return [prefix stringByAppendingFormat:@" %@", [self.dateFormatter stringFromDate:NSDate.date]];
}

- (NSString *)logLevelString
{
  return nil;
}

@end

@interface FBSimulatorLogger_Filter : NSObject <FBSimulatorLogger>

@property (nonatomic, assign, readonly) NSUInteger currentLevel;
@property (nonatomic, copy, readonly) NSIndexSet *enabledLevels;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> underlyingLogger;

@end

@implementation FBSimulatorLogger_Filter

- (instancetype)initWithCurrentLevel:(NSUInteger)currentLevel enabledLevels:(NSIndexSet *)enabledLevels underlyingLogger:(id<FBSimulatorLogger>)underlyingLogger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _currentLevel = currentLevel;
  _enabledLevels = enabledLevels;
  _underlyingLogger = underlyingLogger;

  return self;
}

#pragma mark Public

- (instancetype)log:(NSString *)string
{
  if (![self.enabledLevels containsIndex:self.currentLevel]) {
    return self;
  }
  return [self.underlyingLogger log:string];
}

- (instancetype)logFormat:(NSString *)format, ...
{
  if (![self.enabledLevels containsIndex:self.currentLevel]) {
    return self;
  }

  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self.underlyingLogger log:string];
}

- (id<FBSimulatorLogger>)info
{
  return [[FBSimulatorLogger_Filter alloc] initWithCurrentLevel:ASL_LEVEL_INFO enabledLevels:self.enabledLevels underlyingLogger:self.underlyingLogger.info];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_Filter alloc] initWithCurrentLevel:ASL_LEVEL_DEBUG enabledLevels:self.enabledLevels underlyingLogger:self.underlyingLogger.debug];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_Filter alloc] initWithCurrentLevel:ASL_LEVEL_ERR enabledLevels:self.enabledLevels underlyingLogger:self.underlyingLogger.error];
}

- (id<FBSimulatorLogger>)timestamped
{
  return [[FBSimulatorLogger_Filter alloc] initWithCurrentLevel:self.currentLevel enabledLevels:self.enabledLevels underlyingLogger:self.underlyingLogger.timestamped];
}

@end

@implementation FBSimulatorLogger

+ (id<FBSimulatorLogger>)toNSLogWithMaxLevel:(int)maxLevel
{
  return [[FBSimulatorLogger_Filter alloc]
    initWithCurrentLevel:0
    enabledLevels:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger) maxLevel + 1)]
    underlyingLogger:[[FBSimulatorLogger_NSLog alloc] initWithDateFormatter:nil]];
}

+ (id<FBSimulatorLogger>)toNSLog
{
  return [self toNSLogWithMaxLevel:100];
}

@end
