/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBLogger.h"

static NSMutableArray<id<FBControlCoreLogger>> *GlobalLoggers(void)
{
  static dispatch_once_t onceToken;
  static NSMutableArray<id<FBControlCoreLogger>> *loggers;
  dispatch_once(&onceToken, ^{
    loggers = NSMutableArray.array;
  });
  return loggers;
}

static void AddGlobalLogger(id<FBControlCoreLogger> logger)
{
  NSMutableArray<id<FBControlCoreLogger>> *loggers = GlobalLoggers();
  @synchronized (loggers) {
    [loggers addObject:logger];
  }
}

static void RemoveGlobalLogger(id<FBControlCoreLogger> logger)
{
  NSMutableArray<id<FBControlCoreLogger>> *loggers = GlobalLoggers();
  @synchronized (loggers) {
    [loggers removeObject:logger];
  }
}

@interface FBIDBLogger_Operation : NSObject <FBLogOperation>

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBIDBLogger_Operation

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _logger = logger;
  _queue = queue;


  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [FBMutableFuture.future onQueue:self.queue respondToCancellation:^{
    RemoveGlobalLogger(self.logger);
    return FBFuture.empty;
  }];
}

- (NSString *)futureType
{
  return @"companion_log";
}

@end

@implementation FBIDBLogger

#pragma mark Initializers

+ (dispatch_queue_t)loggerQueue
{
  static dispatch_once_t onceToken;
  static dispatch_queue_t queue;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("com.facebook.idb.logger", DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

+ (instancetype)loggerWithUserDefaults:(NSUserDefaults *)userDefaults
{
  BOOL debugLogging = [[userDefaults stringForKey:@"-log-level"].lowercaseString isEqualToString:@"info"] ? NO : YES;
  id<FBControlCoreLogger> systemLogger = [FBControlCoreLogger systemLoggerWritingToStderr:YES withDebugLogging:debugLogging];
  NSMutableArray<id<FBControlCoreLogger>> *loggers = [NSMutableArray arrayWithObject:[FBControlCoreLogger systemLoggerWritingToStderr:YES withDebugLogging:debugLogging]];

  NSError *error;
  NSString *logFilePath = [userDefaults stringForKey:@"-log-file-path"];
  if (logFilePath) {
    NSURL *logFileURL = [NSURL fileURLWithPath:logFilePath];
    if (![NSFileManager.defaultManager createDirectoryAtURL:logFileURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{} error:&error]) {
      [systemLogger.error logFormat:@"Couldn't create log directory at %@: %@", logFileURL.URLByDeletingLastPathComponent, error];
      exit(1);
    }

    int fileDescriptor = open(logFileURL.path.UTF8String, O_WRONLY | O_APPEND | O_CREAT);
    if (!fileDescriptor) {
      [systemLogger.error logFormat:@"Couldn't create log file at %@ %s", logFileURL.path, strerror(errno)];
      exit(1);
    }

    [loggers addObject:[FBControlCoreLogger loggerToFileDescriptor:fileDescriptor closeOnEndOfFile:YES]];
  }
  FBIDBLogger *logger = [[[FBIDBLogger alloc] initWithLoggers:loggers] withDateFormatEnabled:YES];
  FBControlCoreGlobalConfiguration.defaultLogger = logger;

  return logger;
}

#pragma mark FBCompositeLogger

- (instancetype)initWithLoggers:(NSArray<id<FBControlCoreLogger>> *)loggers
{
  self = [super initWithLoggers:loggers];
  if (!self) {
    return nil;
  }

  return self;
}

- (NSArray<id<FBControlCoreLogger>> *)loggers
{
  NSMutableArray<id<FBControlCoreLogger>> *global = GlobalLoggers();
  NSMutableArray<id<FBControlCoreLogger>> *all = [[super loggers] mutableCopy];
  @synchronized (global)
  {
    [all addObjectsFromArray:global];
  }
  return all;
}

#pragma mark Public Methods

- (FBFuture<id<FBLogOperation>> *)tailToConsumer:(id<FBDataConsumer>)consumer
{
  dispatch_queue_t queue = FBIDBLogger.loggerQueue;
  return [FBFuture onQueue:queue resolveValue:^(NSError **_) {
    id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:consumer];
    id<FBLogOperation> operation =  [[FBIDBLogger_Operation alloc] initWithConsumer:consumer logger:logger queue:queue];
    AddGlobalLogger(logger);
    return operation;
  }];
}

@end
