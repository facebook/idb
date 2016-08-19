/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreFrameworkLoader.h"

#import "FBControlCoreLogger.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreError.h"

@implementation FBControlCoreFrameworkLoader

+ (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if ([NSUserName() isEqualToString:@"root"]) {
    return [[FBControlCoreError
      describeFormat:@"The Frameworks for %@ cannot be loaded from the root user. Don't run this as root.", self.loadingFrameworkName]
      failBool:error];
  }
  return YES;
}

+ (void)loadPrivateFrameworksOrAbort
{
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  NSError *error = nil;
  BOOL success = [self loadPrivateFrameworks:logger.debug error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to private frameworks for %@ with error %@", self.loadingFrameworkName, error];
  abort();
}

+ (NSString *)loadingFrameworkName
{
  return @"FBControlCore";
}

@end
