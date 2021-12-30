/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXcodeDirectory.h"

#import "FBProcess.h"
#import "FBProcessBuilder.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBXcodeDirectory

+ (FBFuture<NSString *> *)xcodeSelectDeveloperDirectory
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  return [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    onQueue:queue fmap:^(FBProcess<NSNull *, NSString *, NSString *> *task) {
      NSString *directory = task.stdOut;
      if ([[NSProcessInfo.processInfo.environment allKeys] containsObject:@"FBXCTEST_XCODE_PATH_OVERRIDE"]) {
        directory = NSProcessInfo.processInfo.environment[@"FBXCTEST_XCODE_PATH_OVERRIDE"];
      }
      if (!directory) {
        return [[FBControlCoreError
          describeFormat:@"Xcode Path could not be determined from `xcode-select`: %@", directory]
          failFuture];
      }
      directory = [directory stringByResolvingSymlinksInPath];

      NSString *helpText = @".\n\n============================\n"
        "%@\n"
        "Please make sure xcode is installed and then run:\n"
        "sudo xcode-select -s $(ls -td /Applications/Xcode* | head -1)/Contents/Developer\n"
        "============================\n\n.";

      if ([directory stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return [[FBControlCoreError
          describeFormat:helpText, @"Empty output for xcode directory returned from `xcode-select -p`: %@", task.stdErr]
          failFuture];
      }
      if ([directory isEqual:@"/Library/Developer/CommandLineTools"]) {
        return [[FBControlCoreError
          describeFormat:helpText, @"`xcode-select -p` returned /Library/Developer/CommandLineTools but idb requires a full xcode install."]
          failFuture];
      }
      if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
        return [[FBControlCoreError
          describeFormat:helpText, [NSString stringWithFormat:@"`xcode-select -p` returned %@ which doesn't exist", directory]]
          failFuture];
      }
      if ([directory isEqualToString:@"/"] ) {
        return [[FBControlCoreError
          describeFormat:helpText, @"`xcode-select -p` returned / which isn't valid."]
          failFuture];
      }
      return [FBFuture futureWithResult:directory];
    }]
    timeout:10 waitingFor:@"xcode-select to complete"];
}

@end
