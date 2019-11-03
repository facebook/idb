/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessFetcher+Helpers.h"

#import <Cocoa/Cocoa.h>

#import "FBProcessInfo.h"
#import "FBControlCoreError.h"
#import "FBFuture+Sync.h"
#import "FBBinaryDescriptor.h"
#import "FBDispatchSourceNotifier.h"

@implementation FBProcessFetcher (Helpers)

+ (FBFuture<FBProcessInfo *> *)obtainProcessInfoForProcessIdentifierInBackground:(pid_t)processIdentifier timeout:(NSTimeInterval)timeout
{
  return [self.backgroundProcessFetcher onQueue:self.backgroundProcessFetchQueue processInfoFor:processIdentifier timeout:timeout];
}

- (nullable FBProcessInfo *)processInfoForJobDictionary:(NSDictionary<NSString *, id> *)jobDictionary
{
  NSNumber *processIdentifierNumber = jobDictionary[@"PID"];
  if (!processIdentifierNumber) {
    return nil;
  }
  return [self processInfoFor:processIdentifierNumber.intValue];
}

- (NSArray<FBProcessInfo *> *)processInfoForRunningApplications:(NSArray<NSRunningApplication *> *)runningApplications
{
  NSMutableArray<FBProcessInfo *> *processes = [NSMutableArray array];
  for (NSRunningApplication *runningApplication in runningApplications) {
    FBProcessInfo *process = [self processInfoFor:runningApplication.processIdentifier];
    if (!process) {
      continue;
    }
    [processes addObject:process];
  }
  return [processes copy];
}

- (BOOL)processIdentifierExists:(pid_t)processIdentifier error:(NSError **)error
{
  FBProcessInfo *actual = [self processInfoFor:processIdentifier];
  if (!actual) {
    return [[FBControlCoreError
      describeFormat:@"Could not find the with pid %d", processIdentifier]
      failBool:error];
  }
  return YES;
}

- (BOOL)processExists:(FBProcessInfo *)process error:(NSError **)error
{
  FBProcessInfo *actual = [self processInfoFor:process.processIdentifier];
  if (!actual) {
    return [[FBControlCoreError
      describeFormat:@"Could not find the with pid %d", process.processIdentifier]
      failBool:error];
  }
  if (![process.launchPath isEqualToString:actual.launchPath]) {
    return [[FBControlCoreError
      describeFormat:@"Processes '%@' and '%@' do not have the same launch path '%@' and '%@'", process.shortDescription, actual.shortDescription, process.launchPath, actual.launchPath]
      failBool:error];
  }
  return YES;
}

- (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForProcessIdentifierToDie:(pid_t)processIdentifier
{
  return [FBFuture onQueue:queue resolveWhen:^ BOOL {
    FBProcessInfo *polledProcess = [self processInfoFor:processIdentifier];
    return polledProcess == nil;
  }];
}

- (NSArray *)runningApplicationsForProcesses:(NSArray *)processes
{
  return [self.processIdentifiersToApplications objectsForKeys:[processes valueForKey:@"processIdentifier"] notFoundMarker:NSNull.null];
}

- (nullable NSRunningApplication *)runningApplicationForProcess:(FBProcessInfo *)process
{
  NSRunningApplication *application = [[self
    runningApplicationsForProcesses:@[process]]
    firstObject];

  if (![application isKindOfClass:NSRunningApplication.class]) {
    return nil;
  }

  return application;
}

+ (NSPredicate *)processesWithLaunchPath:(NSString *)launchPath
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBProcessInfo *processInfo, NSDictionary *_) {
    return [processInfo.launchPath isEqualToString:launchPath];
  }];
}

#pragma mark Private

- (NSDictionary *)processIdentifiersToApplications
{
  NSArray *applications = NSWorkspace.sharedWorkspace.runningApplications;
  NSArray *processIdentifiers = [applications valueForKey:@"processIdentifier"];
  return [NSDictionary dictionaryWithObjects:applications forKeys:processIdentifiers];
}

- (FBFuture<FBProcessInfo *> *)onQueue:(dispatch_queue_t)queue processInfoFor:(pid_t)processIdentifier timeout:(NSTimeInterval)timeout
{
  return [[FBFuture
    onQueue:queue resolveUntil:^{
      FBProcessInfo *process = [self processInfoFor:processIdentifier];
      if (!process) {
        return [[[FBControlCoreError
          describeFormat:@"Could not obtain process info for %d", processIdentifier]
          noLogging]
          failFuture];
      }
      return [FBFuture futureWithResult:process];
    }]
    timeout:timeout waitingFor:@"The process info for %d to become available", processIdentifier];
}

+ (FBProcessFetcher *)backgroundProcessFetcher
{
  static dispatch_once_t onceToken;
  static FBProcessFetcher *processFetcher;
  dispatch_once(&onceToken, ^{
    processFetcher = [FBProcessFetcher new];
  });
  return processFetcher;
}

+ (dispatch_queue_t)backgroundProcessFetchQueue
{
  static dispatch_once_t onceToken;
  static dispatch_queue_t queue;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("com.facebook.processfetcher.background", DISPATCH_QUEUE_SERIAL);
  });
  return queue;
}

@end
