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

@property (nonatomic, assign, readonly) int descriptor;

@end

@implementation FBControlCoreLogger_File

const char *NewLine = "\n";

- (instancetype)initWithFileDescriptor:(int)descriptor
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _descriptor = descriptor;
  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  const char *data = string.UTF8String;
  write(self.descriptor, data, strlen(data));
  write(self.descriptor, NewLine, strlen(NewLine));
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

@property (nonatomic, assign, readonly) int fileDescriptor;
@property (nonatomic, assign, readonly) BOOL debugLogging;
@property (nonatomic, strong, readonly) NSMapTable *queueTable;

@end

@implementation FBASLClientManager

- (instancetype)initWithWritingToFileDescriptor:(int)fileDescriptor debugLogging:(BOOL)debugLogging
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileDescriptor = fileDescriptor;
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

    if (self.fileDescriptor >= STDIN_FILENO) {
      int result = asl_add_output_file(client, self.fileDescriptor, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, filterLimit, ASL_ENCODE_SAFE);
      if (result != 0) {
        asl_log(client, NULL, ASL_LEVEL_ERR, "Failed to add File Descriptor %d to client with error %d", self.fileDescriptor, result);
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

@implementation FBControlCoreLogger

+ (id<FBControlCoreLogger>)systemLoggerWritingToStderrr:(BOOL)writeToStdErr withDebugLogging:(BOOL)debugLogging
{
  int fileDescriptor = writeToStdErr ? STDERR_FILENO : 0;
  return [self systemLoggerWritingToFileDescriptor:fileDescriptor withDebugLogging:debugLogging];
}

+ (id<FBControlCoreLogger>)systemLoggerWritingToFileDescriptor:(int)fileDescriptor withDebugLogging:(BOOL)debugLogging
{
  // asl_add_output_file does not work in macOS 10.2, so we need a composite logger to write to a file descriptor.
  if (NSProcessInfo.processInfo.operatingSystemVersion.minorVersion < 12) {
    return [self aslLoggerWritingToFileDescriptor:fileDescriptor withDebugLogging:debugLogging];
  }
  FBControlCoreLogger_ASL *aslLogger = [self aslLoggerWritingToFileDescriptor:-1 withDebugLogging:debugLogging];
  return [[FBControlCoreLogger_Composite alloc] initWithLoggers:@[
    aslLogger,
    [[FBControlCoreLogger_File alloc] initWithFileDescriptor:fileDescriptor],
  ]];
}

+ (FBControlCoreLogger_ASL *)aslLoggerWritingToFileDescriptor:(int)fileDescriptor withDebugLogging:(BOOL)debugLogging
{
  FBASLClientManager *clientManager = [[FBASLClientManager alloc] initWithWritingToFileDescriptor:fileDescriptor debugLogging:debugLogging];
  asl_object_t client = [clientManager clientHandleForQueue:dispatch_get_main_queue()];
  FBControlCoreLogger_ASL *logger = [[FBControlCoreLogger_ASL alloc] initWithClientManager:clientManager client:client currentLevel:ASL_LEVEL_INFO prefix:nil];
  return logger;
}

@end

#pragma clang diagnostic pop
