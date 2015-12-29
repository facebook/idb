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

@interface FBASLContainer : NSObject

@property (nonatomic, assign, readonly) asl_object_t asl;

@end

@implementation FBASLContainer

- (instancetype)initWithASLObject:(asl_object_t)asl
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _asl = asl;
  return self;
}

- (void)dealloc
{
  asl_close(_asl);
  _asl = NULL;
}

@end

@interface FBSimulatorLogger_ASL : NSObject <FBSimulatorLogger>

@property (nonatomic, strong, readonly) FBASLContainer *aslContainer;
@property (nonatomic, assign, readonly) int currentLevel;

@end

@implementation FBSimulatorLogger_ASL

- (instancetype)initWithASLClient:(FBASLContainer *)aslContainer currentLevel:(int)currentLevel
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _aslContainer = aslContainer;
  _currentLevel = currentLevel;

  return self;
}

- (instancetype)log:(NSString *)string
{
  asl_log(self.aslContainer.asl, NULL, self.currentLevel, "%s", string.UTF8String);
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
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_INFO];
}

- (id<FBSimulatorLogger>)debug
{
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_DEBUG];
}

- (id<FBSimulatorLogger>)error
{
  return [[FBSimulatorLogger_ASL alloc] initWithASLClient:self.aslContainer currentLevel:ASL_LEVEL_ERR];
}

- (id<FBSimulatorLogger>)timestamped
{
  return self;
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

+ (id<FBSimulatorLogger>)toASL
{
  static dispatch_once_t onceToken;
  static FBSimulatorLogger_ASL *logger;
  dispatch_once(&onceToken, ^{
    asl_object_t asl = asl_open("FBSimulatorControl", "com.facebook.fbsimulatorcontrol", ASL_OPT_NO_REMOTE | ASL_OPT_STDERR);
    asl_set_filter(asl, ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG));
    FBASLContainer *aslContainer = [[FBASLContainer alloc] initWithASLObject:asl];
    logger = [[FBSimulatorLogger_ASL alloc] initWithASLClient:aslContainer currentLevel:ASL_LEVEL_INFO];
  });
  return logger;
}

@end
