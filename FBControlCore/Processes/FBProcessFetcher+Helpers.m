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

- (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForProcessIdentifierToDie:(pid_t)processIdentifier
{
  return [FBFuture onQueue:queue resolveWhen:^ BOOL {
    FBProcessInfo *polledProcess = [self processInfoFor:processIdentifier];
    return polledProcess == nil;
  }];
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

#pragma mark Private

- (NSArray *)runningApplicationsForProcesses:(NSArray *)processes
{
  return [self.processIdentifiersToApplications objectsForKeys:[processes valueForKey:@"processIdentifier"] notFoundMarker:NSNull.null];
}

- (NSDictionary *)processIdentifiersToApplications
{
  NSArray *applications = NSWorkspace.sharedWorkspace.runningApplications;
  NSArray *processIdentifiers = [applications valueForKey:@"processIdentifier"];
  return [NSDictionary dictionaryWithObjects:applications forKeys:processIdentifiers];
}

@end
