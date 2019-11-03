/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCrashLogStore.h"

#import "FBCrashLog.h"
#import "FBControlCoreLogger.h"

typedef NSString *FBCrashLogNotificationName NS_STRING_ENUM;

FBCrashLogNotificationName const FBCrashLogAppeared = @"FBCrashLogAppeared";

@interface FBCrashLogStore ()

@property (nonatomic, copy, readonly) NSArray<NSString *> *directories;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBCrashLogInfo *> *ingestedCrashLogs;
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
  _ingestedCrashLogs = NSMutableDictionary.dictionary;
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.crash_store", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Ingestion

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
  FBCrashLogInfo *crashLog = [FBCrashLogInfo fromCrashLogAtPath:path];
  if (!crashLog) {
    [self.logger logFormat:@"Could not obtain crash info for %@", path];
    return nil;
  }
  return  [self ingestCrashLog:crashLog];
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

- (nullable FBCrashLogInfo *)removeCrashLogAtPath:(NSString *)path
{
  NSString *key = path.lastPathComponent;
  FBCrashLogInfo *crashLog = [self ingestedCrashLogWithName:key];
  if (!crashLog) {
    return nil;
  }
  [self.ingestedCrashLogs removeObjectForKey:key];
  return crashLog;
}

#pragma mark Fetching

- (FBCrashLogInfo *)ingestedCrashLogWithName:(NSString *)name
{
  return self.ingestedCrashLogs[name];
}

- (NSArray<FBCrashLogInfo *> *)allIngestedCrashLogs
{
  return self.ingestedCrashLogs.allValues;
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
  return [self.ingestedCrashLogs.allValues filteredArrayUsingPredicate:predicate];
}

- (NSArray<FBCrashLogInfo *> *)pruneCrashLogsMatchingPredicate:(NSPredicate *)predicate
{
  NSMutableArray<NSString *> *keys = NSMutableArray.array;
  NSMutableArray<FBCrashLogInfo *> *crashLogs = NSMutableArray.array;
  for (FBCrashLogInfo *crashLog in self.ingestedCrashLogs.allValues) {
    if (![predicate evaluateWithObject:crashLog]) {
      continue;
    }
    [keys addObject:crashLog.name];
    [crashLogs addObject:crashLog];
  }
  [self.ingestedCrashLogs removeObjectsForKeys:keys];
  return crashLogs;
}

#pragma mark Private

- (BOOL)hasIngestedCrashLogWithName:(NSString *)key
{
  return self.ingestedCrashLogs[key] != nil;
}

- (FBCrashLogInfo *)ingestCrashLog:(FBCrashLogInfo *)crashLog
{
  [self.logger logFormat:@"Ingesting Crash Log %@", crashLog];
  self.ingestedCrashLogs[crashLog.name] = crashLog;
  [NSNotificationCenter.defaultCenter postNotificationName:FBCrashLogAppeared object:crashLog];
  return crashLog;
}

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
    return FBFuture.empty;
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

@end
