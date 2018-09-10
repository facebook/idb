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
#import "FBCrashLogStore.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBControlCoreError.h"

#if defined(__apple_build_version__)

#import <CoreServices/CoreServices.h>

@interface FBCrashLogNotifier_FSEvents : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *directories;
@property (nonatomic, strong, readonly) FBCrashLogStore *store;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readwrite) FSEventStreamRef eventStream;

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
    [notifier.store ingestCrashLogAtPath:path];
  }
}

@implementation FBCrashLogNotifier_FSEvents

- (instancetype)initWithDirectories:(NSArray<NSString *> *)directories store:(FBCrashLogStore *)store logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _directories = directories;
  _store = store;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.crash_logs.fsevents", DISPATCH_QUEUE_SERIAL);

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

  NSMutableArray<NSString *> *pathsToWatch = NSMutableArray.array;
  for (NSString *reportPath in self.directories) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:reportPath]) {
      [pathsToWatch addObject:reportPath];
    }
  }

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

  _store = [FBCrashLogStore storeForDirectories:FBCrashLogInfo.diagnosticReportsPaths logger:logger];

#if defined(__apple_build_version__)
  _fsEvents = [[FBCrashLogNotifier_FSEvents alloc] initWithDirectories:FBCrashLogInfo.diagnosticReportsPaths store:_store logger:logger];
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

- (instancetype)startListening
{
#if defined(__apple_build_version__)
  [self.fsEvents startListening];
#else
  self.sinceDate = NSDate.date;
#endif
  return self;
}

- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForPredicate:(NSPredicate *)predicate
{
  [self startListening];

#if defined(__apple_build_version__)
  return [FBCrashLogNotifier.sharedInstance.fsEvents.store nextCrashLogForMatchingPredicate:predicate];
#else
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.crashlogfetch", DISPATCH_QUEUE_SERIAL);
  return [FBFuture
   onQueue:queue resolveUntil:^{
     FBCrashLogInfo *crashInfo = [[[FBCrashLogInfo
       crashInfoAfterDate:FBCrashLogNotifier.sharedInstance.sinceDate]
       filteredArrayUsingPredicate:predicate]
       firstObject];
     if (!crashInfo) {
       return [[[FBControlCoreError
         describeFormat:@"Crash Log Info for %@ could not be obtained", predicate]
         noLogging]
         failFuture];
     }
     return [FBFuture futureWithResult:crashInfo];
   }];
#endif
}

@end
