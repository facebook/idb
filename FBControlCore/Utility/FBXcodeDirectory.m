/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXcodeDirectory.h"

#import "FBTask.h"
#import "FBTaskBuilder.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBXcodeDirectory

+ (NSString *)xcodeSelectFromCommandLine
{
  return [self new];
}

- (NSString *)xcodePathWithError:(NSError **)error
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
    runSynchronouslyUntilCompletionWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout];
  NSString *directory = [task stdOut];
  if (!directory) {
    return [[FBControlCoreError
      describeFormat:@"Xcode Path could not be determined from `xcode-select`: %@", task.error]
      fail:error];
  }
  directory = [directory stringByResolvingSymlinksInPath];
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBControlCoreError
      describeFormat:@"No Xcode Directory at: %@", directory]
      fail:error];
  }
  if ([directory isEqualToString:@"/"] || [directory isEqualToString:@""]) {
    return [[FBControlCoreError
      describe:@"Xcode Directory is defined as the Root Filesystem. Run xcode-select(1) to set this to a valid Xcode install"]
      fail:error];
  }
  return directory;
}

@end
