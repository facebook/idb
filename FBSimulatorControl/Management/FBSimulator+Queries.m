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
  pid_t process = [FBSimulator launchdSimProcessIdentifierForSimulatorLogs:self.logs query:query];
  return process;
}

- (NSArray *)launchedProcesses
{
  FBProcessQuery *query = [FBProcessQuery new];
  pid_t launchdSimProcessIdentifier = [FBSimulator launchdSimProcessIdentifierForSimulatorLogs:self.logs query:query];
  if (launchdSimProcessIdentifier < 1) {
    return @[];
  }

  return [query subprocessesOf:launchdSimProcessIdentifier];
}

#pragma mark Helpers

+ (pid_t)launchdSimProcessIdentifierForSimulatorLogs:(FBSimulatorLogs *)logs query:(FBProcessQuery *)query
{
  NSString *path = logs.simulatorBootstrap.asPath;
  if (!path) {
    return [self launchdSimProcessIdentifierForSystemLog:logs query:query];
  }

  pid_t pid = [query processWithOpenFileTo:path.UTF8String];
  if (pid < 1) {
    return [self launchdSimProcessIdentifierForSystemLog:logs query:query];
  }
  return pid;
}

+ (pid_t)launchdSimProcessIdentifierForSystemLog:(FBSimulatorLogs *)logs query:(FBProcessQuery *)query
{
  NSString *path = logs.systemLog.asPath;
  if (!path) {
    return -1;
  }

  pid_t syslogdPid = [query processWithOpenFileTo:path.UTF8String];
  if (syslogdPid < 1) {
    return -1;
  }

  return [query parentOf:syslogdPid];
}

@end
