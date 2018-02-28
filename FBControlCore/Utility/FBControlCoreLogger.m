/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreLogger.h"

#import <asl.h>

#import "FBFileConsumer.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

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

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  for (id<FBControlCoreLogger> logger in self.loggers) {
    [logger log:string];
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

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  return [self loggerByApplyingSelector:_cmd object:queue];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return [self loggerByApplyingSelector:_cmd object:prefix];
}

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

@end

@interface FBControlCoreLogger_File : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, nullable, readonly) NSFileHandle *fileHandle;
@property (nonatomic, strong, readonly) NSDateFormatter *dateFormatter;

@end

@implementation FBControlCoreLogger_File

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _dateFormatter = [[NSDateFormatter alloc] init];
  [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSSZZZ"];

  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  if (!self.fileHandle) {
    return self;
  }

  NSString *currentTime = [_dateFormatter stringFromDate:[NSDate date]];
  const char *logLine = [NSString stringWithFormat:@"%@ %@\n", currentTime, string].UTF8String;
  write(self.fileHandle.fileDescriptor, logLine, strlen(logLine));
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

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  return self;
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return self;
}

@end

@interface FBASLClientWrapper : NSObject

@property (nonatomic, assign, readonly) asl_object_t client;

@end

@implementation FBASLClientWrapper

- (instancetype)initWithClient:(asl_object_t)client
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _client = client;
  return self;
}

- (void)dealloc
{
  asl_free(self.client);
}

@end

/**
 Manages asl client handles.
 */
@interface FBASLClientManager : NSObject

@property (nonatomic, strong, nullable, readonly) NSFileHandle *fileHandle;
@property (nonatomic, assign, readonly) BOOL debugLogging;
@property (nonatomic, strong, readonly) NSMapTable *queueTable;

@end

@implementation FBASLClientManager

- (instancetype)initWithWritingToFileHandle:(NSFileHandle *)fileHandle debugLogging:(BOOL)debugLogging
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _debugLogging = debugLogging;
  _queueTable = [NSMapTable mapTableWithKeyOptions:NSMapTableWeakMemory valueOptions:NSMapTableObjectPointerPersonality];

  return self;
}

- (asl_object_t)clientHandleForQueue:(dispatch_queue_t)queue
{
  @synchronized (self)
  {
    FBASLClientWrapper *clientWrapper = [self.queueTable objectForKey:queue];
    if (clientWrapper.client) {
      return clientWrapper.client;
    }

    asl_object_t client = asl_open("FBControlCore", "com.facebook.FBControlCore", 0);
    int filterLimit = self.debugLogging ? ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG) : ASL_FILTER_MASK_UPTO(ASL_LEVEL_INFO);

    if (self.fileHandle) {
      int result = asl_add_output_file(client, self.fileHandle.fileDescriptor, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, filterLimit, ASL_ENCODE_SAFE);
      if (result != 0) {
        asl_log(client, NULL, ASL_LEVEL_ERR, "Failed to add File Descriptor %d to client with error %d", self.fileHandle.fileDescriptor, result);
      }
    }

    clientWrapper = [[FBASLClientWrapper alloc] initWithClient:client];
    [self.queueTable setObject:clientWrapper forKey:queue];
    return client;
  }
}

@end

@interface FBControlCoreLogger_ASL : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) FBASLClientManager *clientManager;
@property (nonatomic, assign, readonly) asl_object_t client;
@property (nonatomic, assign, readonly) int currentLevel;
@property (nonatomic, copy, readonly) NSString *prefix;

@end

@implementation FBControlCoreLogger_ASL

- (instancetype)initWithClientManager:(FBASLClientManager *)clientManager client:(asl_object_t)client currentLevel:(int)currentLevel prefix:(NSString *)prefix
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _clientManager = clientManager;
  _client = client;
  _currentLevel = currentLevel;
  _prefix = prefix;

  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  string = self.prefix ? [self.prefix stringByAppendingFormat:@" %@", string] : string;
  asl_log(self.client, NULL, self.currentLevel, string.UTF8String, NULL);
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
  return [[FBControlCoreLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_INFO prefix:self.prefix];
}

- (id<FBControlCoreLogger>)debug
{
  return [[FBControlCoreLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_DEBUG prefix:self.prefix];
}

- (id<FBControlCoreLogger>)error
{
  return [[FBControlCoreLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:ASL_LEVEL_ERR prefix:self.prefix];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  asl_object_t client = [self.clientManager clientHandleForQueue:queue];
  return [[FBControlCoreLogger_ASL alloc] initWithClientManager:self.clientManager client:client currentLevel:self.currentLevel prefix:self.prefix];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return [[FBControlCoreLogger_ASL alloc] initWithClientManager:self.clientManager client:self.client currentLevel:self.currentLevel prefix:prefix];
}

@end

@interface FBControlCoreLogger_Consumer : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;

@end

@implementation FBControlCoreLogger_Consumer

- (instancetype)initWithConsumer:(id<FBFileConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

#pragma mark Protocol Implementation

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  [self.consumer consumeData:data];
  data = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
  [self.consumer consumeData:data];
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
  return [[self.class alloc] initWithConsumer:self.consumer];
}

- (id<FBControlCoreLogger>)debug
{
  return [[self.class alloc] initWithConsumer:self.consumer];
}

- (id<FBControlCoreLogger>)error
{
  return [[self.class alloc] initWithConsumer:self.consumer];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  return [[self.class alloc] initWithConsumer:self.consumer];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return [[self.class alloc] initWithConsumer:self.consumer];
}

@end

@implementation FBControlCoreLogger

+ (id<FBControlCoreLogger>)systemLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  NSFileHandle *fileHandle = writeToStdErr ? NSFileHandle.fileHandleWithStandardError : nil;
  return [self systemLoggerWritingToFileHandle:fileHandle withDebugLogging:debugLogging];
}

+ (id<FBControlCoreLogger>)systemLoggerWritingToFileHandle:(nullable NSFileHandle *)fileHandle withDebugLogging:(BOOL)debugLogging
{
  // asl_add_output_file does not work in macOS 10.2, so we need a composite logger to write to a file descriptor.
  if (NSProcessInfo.processInfo.operatingSystemVersion.minorVersion < 12) {
    return [self aslLoggerWritingToFileHandle:fileHandle withDebugLogging:debugLogging];
  }
  FBControlCoreLogger_ASL *aslLogger = [self aslLoggerWritingToFileHandle:nil withDebugLogging:debugLogging];
  return [self compositeLoggerWithLoggers:@[
    aslLogger,
    [[FBControlCoreLogger_File alloc] initWithFileHandle:fileHandle],
  ]];
}

+ (FBControlCoreLogger_ASL *)aslLoggerWritingToFileHandle:(nullable NSFileHandle *)fileHandle withDebugLogging:(BOOL)debugLogging
{
  FBASLClientManager *clientManager = [[FBASLClientManager alloc] initWithWritingToFileHandle:fileHandle debugLogging:debugLogging];
  asl_object_t client = [clientManager clientHandleForQueue:dispatch_get_main_queue()];
  FBControlCoreLogger_ASL *logger = [[FBControlCoreLogger_ASL alloc] initWithClientManager:clientManager client:client currentLevel:ASL_LEVEL_INFO prefix:nil];
  return logger;
}

+ (id<FBControlCoreLogger>)compositeLoggerWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers
{
  return [[FBControlCoreLogger_Composite alloc] initWithLoggers:loggers];
}

+ (id<FBControlCoreLogger>)loggerToConsumer:(id<FBFileConsumer>)consumer
{
  return [[FBControlCoreLogger_Consumer alloc] initWithConsumer:consumer];
}

@end

#pragma clang diagnostic pop
