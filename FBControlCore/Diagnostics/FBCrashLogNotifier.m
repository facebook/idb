/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCrashLogNotifier.h"

#import "FBCrashLogInfo.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBControlCoreError.h"

typedef NSString *FBCrashLogNotificationName NS_STRING_ENUM;

FBCrashLogNotificationName const FBCrashLogAppeared = @"FBCrashLogAppeared";

#if defined(__apple_build_version__)

#import <CoreServices/CoreServices.h>

@interface FBCrashLogNotifier_FSEvents : NSObject

@property (nonatomic, copy, readonly) NSString *directory;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, FBCrashLogInfo *> *ingestedCrashLogs;
@property (nonatomic, assign, readwrite) FSEventStreamRef eventStream;

- (void)ingestCrashLogAtPath:(NSString *)path;

@end

static void EventStreamCallback(
  ConstFSEventStreamRef streamRef,
  FBCrashLogNotifier_FSEvents *notifier,
  size_t numEvents,
  NSArray<NSString *> *eventPaths,
  const FSEventStreamEventFlags *eventFlags,
  const FSEventStreamEventId *eventIds
){
  for (size_t index = 0; index < numEvents; index++) {
    NSString *path = eventPaths[index];
    [notifier ingestCrashLogAtPath:path];
  }
}

@implementation FBCrashLogNotifier_FSEvents

- (instancetype)initWithDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _directory = directory;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.crash_logs.fsevents", DISPATCH_QUEUE_SERIAL);
  _ingestedCrashLogs = [NSMutableDictionary dictionary];

  return self;
}

- (void)startListening
{
  if (self.eventStream) {
    return;
  }

  FSEventStreamContext context = {
    .version = 0,
    .info = (void *) CFBridgingRetain(self),
    .retain = CFRetain,
    .release = CFRelease,
    .copyDescription = NULL,
  };
  NSArray<NSString *> *pathsToWatch = @[self.directory];

  FSEventStreamRef eventStream = FSEventStreamCreate(
    NULL, // Allocator
    (FSEventStreamCallback) EventStreamCallback, // Callback
    &context,  // Context
    CFBridgingRetain(pathsToWatch), // Paths to watch
    kFSEventStreamEventIdSinceNow,  // Since When
    0,  // Latency
    kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
  );
  FSEventStreamSetDispatchQueue(eventStream, self.queue);
  Boolean started = FSEventStreamStart(eventStream);
  NSAssert(started, @"Event Stream could not be started");
  self.eventStream = eventStream;
}

- (void)ingestCrashLogAtPath:(NSString *)path
{
  FBCrashLogInfo *crashLogInfo = [FBCrashLogInfo fromCrashLogAtPath:path];
  if (!crashLogInfo) {
    [self.logger logFormat:@"Could not obtain crash info for %@", path];
    return;
  }
  [self.logger logFormat:@"Ingesting Crash Log %@", crashLogInfo];
  self.ingestedCrashLogs[@(crashLogInfo.processIdentifier)] = crashLogInfo;
  [NSNotificationCenter.defaultCenter postNotificationName:FBCrashLogAppeared object:crashLogInfo];
}

- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForProcessIdentifier:(pid_t)processIdentifier
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<FBCrashLogInfo *> * {
      FBCrashLogInfo *info = self.ingestedCrashLogs[@(processIdentifier)];
      if (info) {
        return [FBFuture futureWithResult:info];
      }
      return [FBCrashLogNotifier_FSEvents oneshotCrashLogNotificationForProcessIdentifier:processIdentifier queue:self.queue];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)oneshotCrashLogNotificationForProcessIdentifier:(pid_t)processIdentifier queue:(dispatch_queue_t)queue
{
  __weak NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  FBMutableFuture<FBCrashLogInfo *> *future = [FBMutableFuture future];

  id __block observer = [notificationCenter
   addObserverForName:FBCrashLogAppeared
   object:nil
   queue:NSOperationQueue.mainQueue
   usingBlock:^(NSNotification *notification) {
     FBCrashLogInfo *crashLog = notification.object;
     if (crashLog.processIdentifier != processIdentifier) {
       return;
     }
     [future resolveWithResult:crashLog];
     [notificationCenter removeObserver:observer];
   }];

  return [future onQueue:queue respondToCancellation:^{
    [notificationCenter removeObserver:observer];
    return [FBFuture futureWithResult:NSNull.null];
  }];
}

@end

#endif

@interface FBCrashLogNotifier ()

#if defined(__apple_build_version__)
@property (nonatomic, strong, readonly) FBCrashLogNotifier_FSEvents *fsEvents;
#else
@property (nonatomic, copy, readwrite) NSDate *sinceDate;
#endif

@end

@implementation FBCrashLogNotifier

#pragma mark Initializers

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

#if defined(__apple_build_version__)
  _fsEvents = [[FBCrashLogNotifier_FSEvents alloc] initWithDirectory:FBCrashLogInfo.diagnosticReportsPath logger:logger];
#else
  _sinceDate = NSDate.date;
#endif

  return self;
}

+ (instancetype)sharedInstance
{
  static dispatch_once_t onceToken;
  static FBCrashLogNotifier *notifier;
  dispatch_once(&onceToken, ^{
    notifier = [[FBCrashLogNotifier alloc] initWithLogger:FBControlCoreGlobalConfiguration.defaultLogger];
  });
  return notifier;
}

#pragma mark Public Methods

+ (void)startListening
{
#if defined(__apple_build_version__)
  [FBCrashLogNotifier.sharedInstance.fsEvents startListening];
#else
  FBCrashLogNotifier.sharedInstance.sinceDate = NSDate.date;
#endif
}

+ (FBFuture<FBCrashLogInfo *> *)nextCrashLogForProcessIdentifier:(pid_t)processIdentifier
{
  [self startListening];
#if defined(__apple_build_version__)
  return [FBCrashLogNotifier.sharedInstance.fsEvents nextCrashLogForProcessIdentifier:processIdentifier];
#else
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.crashlogfetch", DISPATCH_QUEUE_SERIAL);
  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
   return processIdentifier == crashLogInfo.processIdentifier;
  }];
  return [FBFuture
   onQueue:queue resolveUntil:^{
     FBCrashLogInfo *crashInfo = [[[FBCrashLogInfo
       crashInfoAfterDate:FBCrashLogNotifier.sharedInstance.sinceDate]
       filteredArrayUsingPredicate:crashLogInfoPredicate]
       firstObject];
     if (!crashInfo) {
       return [[[FBControlCoreError
         describeFormat:@"Crash Info for %d could not be obtained", processIdentifier]
         noLogging]
         failFuture];
     }
     return [FBFuture futureWithResult:crashInfo];
   }];
#endif
}

@end
