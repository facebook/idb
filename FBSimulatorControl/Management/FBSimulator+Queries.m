/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Queries.h"

#import <CoreSimulator/SimDevice.h>

#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimulatorLogs.h"
#import "FBTaskExecutor.h"
#import "FBWritableLog.h"

@implementation FBSimulator (Queries)

- (pid_t)launchdSimProcessIdentifier
{
  FBProcessQuery *query = [FBProcessQuery new];
  pid_t process = [FBSimulator launchdSimProcessIdentifierForUDID:self.udid query:query];
  return process;
}

- (NSArray *)launchedProcesses
{
  FBProcessQuery *query = [FBProcessQuery new];
  pid_t launchdSimProcessIdentifier = [FBSimulator launchdSimProcessIdentifierForUDID:self.udid query:query];
  if (launchdSimProcessIdentifier < 1) {
    return @[];
  }

  return [query subprocessesOf:launchdSimProcessIdentifier];
}

#pragma mark Helpers

+ (pid_t)launchdSimProcessIdentifierForUDID:(NSString *)udid query:(FBProcessQuery *)query
{
  for (id<FBProcessInfo> info in [query processesWithProcessName:@"launchd_sim"]) {
    NSString *udidContainingString = info.environment[@"XPC_SIMULATOR_LAUNCHD_NAME"];
    if ([udidContainingString rangeOfString:udid].location != NSNotFound) {
      return info.processIdentifier;
    }
  }
  return -1;
}

@end
