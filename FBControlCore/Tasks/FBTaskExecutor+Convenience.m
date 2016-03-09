/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTaskExecutor+Convenience.h"

#import "FBControlCoreGlobalConfiguration.h"
#import "FBTask.h"
#import "FBTaskExecutor+Private.h"

@implementation FBTaskExecutor (Convenience)

- (NSString *)executeShellCommand:(NSString *)commandString
{
  return [self executeShellCommand:commandString returningError:nil];
}

- (NSString *)executeShellCommand:(NSString *)commandString returningError:(NSError **)error
{
  id<FBTask> command = [self shellTask:commandString];
  [command startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];

  if (command.error) {
    if (error) {
      *error = command.error;
    }
    return nil;
  }
  return command.stdOut;
}

- (BOOL)repeatedlyRunCommand:(NSString *)commandString withError:(NSError **)error untilTrue:( BOOL(^)(NSString *stdOut) )block
{
  @autoreleasepool {
    NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:FBControlCoreGlobalConfiguration.regularTimeout];
    while ([endDate timeIntervalSinceNow] < 0) {
      NSError *innerError = nil;
      NSString *stdOut = [self executeShellCommand:commandString returningError:&innerError];
      if (!stdOut) {
        if (error) {
          *error = innerError;
        }
        return NO;
      }
      if (block(stdOut)) {
        return YES;
      }

      CFRunLoopRun();
    }
  }

  if (error) {
    *error = [FBTaskExecutor errorForDescription:[NSString stringWithFormat:@"Timed out waiting to validate command %@", commandString]];
  }

  return YES;
}

@end
