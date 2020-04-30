/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXcodeDirectory.h"

#import "FBTask.h"
#import "FBTaskBuilder.h"
#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBXcodeDirectory

#pragma mark Initializers

+ (FBXcodeDirectory *)xcodeSelectFromCommandLine
{
  return [self new];
}

#pragma mark Public Methods

- (FBFuture<NSString *> *)xcodePath
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask *task) {
      NSString *directory = [task stdOut];
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
          describeFormat:helpText, @"No Xcode Directory returned from `xcode-select -p`."]
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
    }];
}

@end
