/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCrashLogNotifier.h"

#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBCrashLog.h"
#import "FBCrashLogStore.h"

@interface FBCrashLogNotifier ()

@property (nonatomic, readwrite, copy) NSDate *sinceDate;

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
  _sinceDate = NSDate.date;

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

- (BOOL)startListening:(BOOL)onlyNew
{
  self.sinceDate = onlyNew ? NSDate.date : [NSDate distantPast];
  return YES;
}

- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForPredicate:(NSPredicate *)predicate
{
  [self startListening:YES];

  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.crashlogfetch", DISPATCH_QUEUE_SERIAL);
  return [FBFuture
          onQueue:queue
          resolveUntil:^{
            FBCrashLogInfo *crashInfo = [[[FBCrashLogInfo
                                           crashInfoAfterDate:FBCrashLogNotifier.sharedInstance.sinceDate
                                           logger:nil]
                                          filteredArrayUsingPredicate:predicate]
                                         firstObject];
            if (!crashInfo) {
              return [[FBControlCoreError
                       describe:[NSString stringWithFormat:@"Crash Log Info for %@ could not be obtained", predicate]]
                      failFuture];
            }
            [self.store ingestCrashLogAtPath:crashInfo.crashPath];
            return [FBFuture futureWithResult:crashInfo];
          }];
}

@end
