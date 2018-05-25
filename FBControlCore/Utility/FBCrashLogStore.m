/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCrashLogStore.h"

#import "FBCrashLogInfo.h"
#import "FBControlCoreLogger.h"

typedef NSString *FBCrashLogNotificationName NS_STRING_ENUM;

FBCrashLogNotificationName const FBCrashLogAppeared = @"FBCrashLogAppeared";

@interface FBCrashLogStore ()

@property (nonatomic, copy, readonly) NSString *directory;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableArray<FBCrashLogInfo *> *ingestedCrashLogs;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBCrashLogStore

#pragma mark Initializers

+ (instancetype)storeForDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDirectory:directory logger:logger];
}

- (instancetype)initWithDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _directory = directory;
  _logger = logger;
  _ingestedCrashLogs = NSMutableArray.array;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.crash_store", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Public Methods

- (FBCrashLogInfo *)ingestCrashLogAtPath:(NSString *)path
{
  FBCrashLogInfo *crashLogInfo = [FBCrashLogInfo fromCrashLogAtPath:path];
  if (!crashLogInfo) {
    [self.logger logFormat:@"Could not obtain crash info for %@", path];
    return nil;
  }
  [self.logger logFormat:@"Ingesting Crash Log %@", crashLogInfo];
  [self.ingestedCrashLogs addObject:crashLogInfo];
  [NSNotificationCenter.defaultCenter postNotificationName:FBCrashLogAppeared object:crashLogInfo];
  return crashLogInfo;
}

- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForMatchingPredicate:(NSPredicate *)predicate
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<FBCrashLogInfo *> * {
      return [FBCrashLogStore oneshotCrashLogNotificationForPredicate:predicate queue:self.queue];
    }];
}

#pragma mark Private

+ (FBFuture<FBCrashLogInfo *> *)oneshotCrashLogNotificationForPredicate:(NSPredicate *)predicate queue:(dispatch_queue_t)queue
{
  __weak NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
  FBMutableFuture<FBCrashLogInfo *> *future = [FBMutableFuture future];

  id __block observer = [notificationCenter
    addObserverForName:FBCrashLogAppeared
    object:nil
    queue:NSOperationQueue.mainQueue
    usingBlock:^(NSNotification *notification) {
      FBCrashLogInfo *crashLog = notification.object;
      if (![predicate evaluateWithObject:crashLog]) {
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
