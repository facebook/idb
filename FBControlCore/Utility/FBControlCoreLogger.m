/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreLogger.h"

#import "FBDataConsumer.h"
#import "FBFileWriter.h"
#import "FBControlCoreLogger+OSLog.h"

@interface FBControlCoreLogger_NSLog : NSObject <FBControlCoreLogger>

@end

@implementation FBControlCoreLogger_NSLog

@synthesize name = _name;
@synthesize level = _level;

- (instancetype)initWithname:(NSString *)name level:(FBControlCoreLogLevel)level
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _level = level;

  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)message
{
  NSString *string = self.name ? [NSString stringWithFormat:@"[%@] %@", self.name, message] : message;
  NSLog(@"%@", string);
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return self;
}

- (id<FBControlCoreLogger>)debug
{
  return self;
}

- (id<FBControlCoreLogger>)error
{
  return self;
}

- (id<FBControlCoreLogger>)withName:(NSString *)name
{
  return [[self.class alloc] initWithname:name level:self.level];
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)dateFormat
{
  return self;
}

@end

@interface FBControlCoreLogger_Composite : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) NSArray<id<FBControlCoreLogger>> *loggers;

@end

@implementation FBControlCoreLogger_Composite

- (instancetype)initWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _loggers = loggers;

  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)message
{
  message = [FBControlCoreLogger loggableStringLine:message];
  if (!message) {
    return self;
  }
  for (id<FBControlCoreLogger> logger in self.loggers) {
    [logger log:message];
  }
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [self loggerByApplyingSelector:_cmd];
}

- (id<FBControlCoreLogger>)debug
{
  return [self loggerByApplyingSelector:_cmd];
}

- (id<FBControlCoreLogger>)error
{
  return [self loggerByApplyingSelector:_cmd];
}

- (id<FBControlCoreLogger>)withName:(NSString *)name
{
  return [self loggerByApplyingSelector:_cmd object:name];
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)dateFormat
{
  return [self loggerByApplyingSelector:_cmd object:@(dateFormat)];
}

- (NSString *)name
{
  return nil;
}

- (FBControlCoreLogLevel)level
{
  return FBControlCoreLogLevelMultiple;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

- (id<FBControlCoreLogger>)loggerByApplyingSelector:(SEL)selector
{
  NSMutableArray<id<FBControlCoreLogger>> *loggers = [NSMutableArray arrayWithCapacity:self.loggers.count];
  for (id<FBControlCoreLogger> logger in self.loggers) {
    [loggers addObject:[logger performSelector:selector]];
  }
  return [[FBControlCoreLogger_Composite alloc] initWithLoggers:[loggers copy]];
}

- (id<FBControlCoreLogger>)loggerByApplyingSelector:(SEL)selector object:(id)object
{
  NSMutableArray<id<FBControlCoreLogger>> *loggers = [NSMutableArray arrayWithCapacity:self.loggers.count];
  for (id<FBControlCoreLogger> logger in self.loggers) {
    [loggers addObject:[logger performSelector:selector withObject:object]];
  }
  return [[FBControlCoreLogger_Composite alloc] initWithLoggers:[loggers copy]];
}

#pragma clang diagnostic pop

@end

@interface FBControlCoreLogger_Consumer : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readonly, nullable) NSDateFormatter *dateFormatter;

@end

@implementation FBControlCoreLogger_Consumer

@synthesize name = _name;
@synthesize level = _level;

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer name:(NSString *)name dateFormatter:(NSDateFormatter *)dateFormatter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _name = name;
  _dateFormatter = dateFormatter;

  return self;
}

#pragma mark Protocol Implementation

- (id<FBControlCoreLogger>)log:(NSString *)message
{
  message = [FBControlCoreLogger loggableStringLine:message];
  if (!message) {
    return self;
  }
  NSMutableString *string = [NSMutableString string];
  if (self.dateFormatter) {
    [string appendFormat:@"%@ ", [self.dateFormatter stringFromDate:NSDate.date]];
  }
  if (self.name) {
    [string appendFormat:@"[%@] ", self.name];
  }
  [string appendString:message];
  [string appendString:@"\n"];
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  @synchronized(self.consumer)
  {
    [self.consumer consumeData:data];
  }
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [[self.class alloc] initWithConsumer:self.consumer name:self.name dateFormatter:self.dateFormatter];
}

- (id<FBControlCoreLogger>)debug
{
  return [[self.class alloc] initWithConsumer:self.consumer name:self.name dateFormatter:self.dateFormatter];
}

- (id<FBControlCoreLogger>)error
{
  return [[self.class alloc] initWithConsumer:self.consumer name:self.name dateFormatter:self.dateFormatter];
}

- (id<FBControlCoreLogger>)withName:(NSString *)name
{
  return [[self.class alloc] initWithConsumer:self.consumer name:name dateFormatter:self.dateFormatter];
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled
{
  NSDateFormatter *dateFormatter = nil;
  if (enabled) {
    dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSSZZZ"];
  }
  return [[self.class alloc] initWithConsumer:self.consumer name:self.name dateFormatter:dateFormatter];
}

@end

@implementation FBControlCoreLogger

#pragma mark Public

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

+ (id<FBControlCoreLogger>)systemLoggerWritingToStderr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging;
{
  // Use the appropriate logger.
  FBControlCoreLogLevel level = debugLogging ? FBControlCoreLogLevelDebug : FBControlCoreLogLevelInfo;
  id<FBControlCoreLogger> systemLogger = [self osLoggerWithLevel:level] ?: [FBControlCoreLogger_NSLog new];

  // If we don't care about stderr, just return the system logger.
  if (!writeToStdErr) {
    return systemLogger;
  }

  // If the system logger will log to stderr in the current build environment or runtime
  // don't bother adding a logger that will additionally log to stderr.
  if (FBControlCoreLogger.systemLoggerWillLogToStdErr) {
    return systemLogger;
  }

  // In contexts where we run without mirroring enabled.
  return [self compositeLoggerWithLoggers:@[
    systemLogger,
    [self loggerToFileHandle:NSFileHandle.fileHandleWithStandardError],
  ]];
}

#pragma clang diagnostic pop

+ (id<FBControlCoreLogger>)compositeLoggerWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers
{
  return [[FBControlCoreLogger_Composite alloc] initWithLoggers:loggers];
}

+ (id<FBControlCoreLogger>)loggerToConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreLogger_Consumer alloc] initWithConsumer:consumer name:nil dateFormatter:nil];
}

+ (id<FBControlCoreLogger>)loggerToFileHandle:(NSFileHandle *)fileHandle
{
  id<FBDataConsumer> consumer = [FBFileWriter syncWriterWithFileHandle:fileHandle];
  return [[FBControlCoreLogger_Consumer alloc] initWithConsumer:consumer name:nil dateFormatter:nil];
}

+ (NSString *)loggableStringLine:(NSString *)string
{
  if (!string) {
    return nil;
  }
  string = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (string.length == 0) {
    return nil;
  }
  return string;
}

@end
