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

static NSString * const HelpText = @".\n\n============================\n"
  "Please make sure xcode is installed and then run:\n"
  "sudo xcode-select -s $(ls -td /Applications/Xcode* | head -1)/Contents/Developer\n"
  "============================\n\n.";

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
      if ([directory stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
        return [[FBControlCoreError
          describeFormat:@"Empty output for xcode directory returned from `xcode-select -p`: %@%@", task.stdErr, HelpText]
          failFuture];
      }
      directory = [directory stringByResolvingSymlinksInPath];
    
      NSError *error = nil;
      if (![self isValidXcodeDirectory:directory error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:directory];
    }]
    timeout:10 waitingFor:@"xcode-select to complete"];
}

+ (nullable NSString *)symlinkedDeveloperDirectoryWithError:(NSError **)error
{
  NSString *directory = [@"/var/db/xcode_select_link" stringByResolvingSymlinksInPath];
  if (![self isValidXcodeDirectory:directory error:error]) {
    return nil;
  }
  return directory;
}

+ (BOOL)isValidXcodeDirectory:(NSString *)directory error:(NSError **)error
{
  if (!directory) {
    return [[FBControlCoreError
      describe:@"Xcode Path is nil"]
      failBool:error];
  }
  if ([directory isEqual:@"/Library/Developer/CommandLineTools"]) {
    return [[FBControlCoreError
      describeFormat:@"`xcode-select -p` returned /Library/Developer/CommandLineTools but idb requires a full xcode install.%@", HelpText]
      failBool:error];
  }
  if (![NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return [[FBControlCoreError
      describeFormat:@"`xcode-select -p` returned %@ which doesn't exist%@", directory, HelpText]
      failBool:error];
  }
  if ([directory isEqualToString:@"/"] ) {
    return [[FBControlCoreError
      describeFormat:@"`xcode-select -p` returned / which isn't valid.%@", HelpText]
      failBool:error];
  }
  return YES;
}

@end
