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

@property (nonatomic, copy, readonly) NSArray<NSString *> *directories;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableArray<FBCrashLogInfo *> *ingestedCrashLogs;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBCrashLogStore

#pragma mark Initializers

+ (instancetype)storeForDirectories:(NSArray<NSString *> *)directories logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithDirectories:directories logger:logger];
}

- (instancetype)initWithDirectories:(NSArray<NSString *> *)directories logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _directories = directories;
  _logger = logger;
  _ingestedCrashLogs = NSMutableArray.array;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.crash_store", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Public Methods

- (NSArray<FBCrashLogInfo *> *)ingestAllExistingInDirectory
{
  NSMutableArray<FBCrashLogInfo *> *ingested = NSMutableArray.array;

  for (NSString *directory in self.directories) {
    NSArray<FBCrashLogInfo *> *crashLogs = [self ingestCrashLogInDirectory:directory];
    [ingested addObjectsFromArray:crashLogs];
  }
  return [ingested copy];
}

- (FBCrashLogInfo *)ingestCrashLogAtPath:(NSString *)path
{
  if ([self hasIngestedCrashLogWithName:path.lastPathComponent]) {
    return nil;
  }
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

- (nullable FBCrashLogInfo *)ingestCrashLogData:(NSData *)data name:(NSString *)name
{
  if ([self hasIngestedCrashLogWithName:name]) {
    return nil;
  }
  if (![FBCrashLogInfo isParsableCrashLog:data]) {
    return nil;
  }
  for (NSString *directory in self.directories) {
    NSString *destination = [directory stringByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
      if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) {
        continue;
      }
    }
    if (![data writeToFile:destination atomically:YES]) {
      continue;
    }
    return [self ingestCrashLogAtPath:destination];
  }

  return nil;
}

- (BOOL)hasIngestedCrashLogWithName:(NSString *)key
{
  return [self.ingestedNames containsObject:key];
}

- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForMatchingPredicate:(NSPredicate *)predicate
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<FBCrashLogInfo *> * {
      return [FBCrashLogStore oneshotCrashLogNotificationForPredicate:predicate queue:self.queue];
    }];
}

- (NSArray<FBCrashLogInfo *> *)ingestedCrashLogsMatchingPredicate:(NSPredicate *)predicate
{
  return [self.ingestedCrashLogs filteredArrayUsingPredicate:predicate];
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

- (NSArray<FBCrashLogInfo *> *)ingestCrashLogInDirectory:(NSString *)directory
{
  NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
  if (!contents) {
    return @[];
  }

  NSMutableArray<FBCrashLogInfo *> *ingested = NSMutableArray.array;
  for (NSString *path in contents) {
    FBCrashLogInfo *crash = [self ingestCrashLogAtPath:[directory stringByAppendingPathComponent:path]];
    if (!crash) {
      continue;
    }
    [ingested addObject:crash];
  }
  return [ingested copy];
}

- (NSSet<NSString *> *)ingestedNames
{
  return [NSSet setWithArray:[self.ingestedCrashLogs valueForKeyPath:@"name"]];
}

@end
