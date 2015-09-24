/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Queries.h"

#import "FBSimulatorProcess.h"
#import "FBTaskExecutor.h"

@implementation FBSimulator (Queries)

- (BOOL)hasActiveLaunchdSim
{
  return self.launchdSimProcessIdentifier > 1;
}

- (NSArray *)launchedProcesses
{
  NSInteger launchdSimProcessIdentifier = self.launchdSimProcessIdentifier;
  if (launchdSimProcessIdentifier < 1) {
    return @[];
  }

  NSString *allProcesses = [[[FBTaskExecutor.sharedInstance
    taskWithLaunchPath:@"/usr/bin/pgrep" arguments:@[@"-lfP", [@(launchdSimProcessIdentifier) stringValue]]]
    startSynchronouslyWithTimeout:10]
    stdOut];

  NSArray *checkingResults = [self.class.longFormPgrepRegex matchesInString:allProcesses options:0 range:NSMakeRange(0, allProcesses.length)];
  NSMutableArray *processes = [NSMutableArray array];
  for (NSTextCheckingResult *result in checkingResults) {
    NSInteger processIdentifier = [[allProcesses substringWithRange:[result rangeAtIndex:1]] integerValue];
    if (processIdentifier < 1) {
      continue;
    }
    NSString *launchPath = [allProcesses substringWithRange:[result rangeAtIndex:2]];
    [processes addObject:[FBFoundProcess withProcessIdentifier:processIdentifier launchPath:launchPath]];
  }
  return [processes copy];
}

+ (NSRegularExpression *)longFormPgrepRegex
{
  static dispatch_once_t onceToken;
  static NSRegularExpression *regex;
  dispatch_once(&onceToken, ^{
    regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+) (.+)" options:0 error:nil];
    NSCAssert(regex, @"Regex should compile");
  });
  return regex;
}

@end
