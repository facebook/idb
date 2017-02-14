/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCodesignProvider.h"

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreError.h"

static NSString *const CDHashPrefix = @"CDHash=";

@implementation FBCodesignProvider

+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName
{
  return [[self alloc] initWithIdentityName:identityName];
}

+ (instancetype)codeSignCommandWithAdHocIdentity
{
  return [[self alloc] initWithIdentityName:@"-"];
}

- (instancetype)initWithIdentityName:(NSString *)identityName
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identityName = identityName;
  return self;
}

#pragma mark - FBCodesignProvider protocol

+ (FBLogSearchPredicate *)logSearchPredicateForCDHash
{
  return [FBLogSearchPredicate substrings:@[CDHashPrefix]];
}

- (BOOL)signBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
  FBTask *task = [[FBTaskBuilder taskWithLaunchPath:@"/usr/bin/codesign" arguments:@[@"-s", self.identityName, @"-f", bundlePath]]
                      startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];
  if (task.error && error) {
    *error = task.error;
  }
  return [task wasSuccessful];
}

- (BOOL)recursivelySignBundleAtPath:(NSString *)bundlePath error:(NSError **)error {
  NSMutableArray<NSString *> *pathsToSign = [NSMutableArray arrayWithObject:bundlePath];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *frameworksPath = [bundlePath stringByAppendingString:@"/Frameworks/"];
  if ([fileManager fileExistsAtPath:frameworksPath]) {
    NSError *fileSystemError;
    for (NSString *frameworkPath in [fileManager contentsOfDirectoryAtPath:frameworksPath error:&fileSystemError]) {
      [pathsToSign addObject:[frameworksPath stringByAppendingString:frameworkPath]];
    }

    if (fileSystemError) {
      if (error) {
        *error = fileSystemError;
      }
      return NO;
    }
  }

  for (NSString *pathToSign in pathsToSign) {
    if (![self signBundleAtPath:pathToSign error:error]) {
      return NO;
    }
  }
  return YES;
}


- (nullable NSString *)cdHashForBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
  FBTask *task = [[FBTaskBuilder
    taskWithLaunchPath:@"/usr/bin/codesign" arguments:@[@"-dvvvv", bundlePath]]
    startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout];
  if (task.error) {
    return [[[FBControlCoreError
      describe:@"Could not execute codesign"]
      causedBy:task.error]
      fail:error];
  }
  NSString *output = task.stdErr;
  NSString *cdHash = [[[FBLogSearch
    withText:output predicate:FBCodesignProvider.logSearchPredicateForCDHash]
    firstMatchingLine]
    stringByReplacingOccurrencesOfString:CDHashPrefix withString:@""];
  if (!cdHash) {
    return [[[FBControlCoreError
      describeFormat:@"Could not find '%@' in output: %@", CDHashPrefix, output]
      causedBy:task.error]
      fail:error];
  }
  return cdHash;
}

@end
