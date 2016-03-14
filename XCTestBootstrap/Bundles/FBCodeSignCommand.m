/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCodeSignCommand.h"

@implementation FBCodeSignCommand

+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName
{
  FBCodeSignCommand *command = [self.class new];
  command->_identityName = identityName;
  return command;
}


#pragma mark - FBCodesignProvider protocol

- (BOOL)signBundleAtPath:(NSString *)bundlePath
{
  NSTask *signTask = [NSTask new];
  signTask.launchPath = @"/usr/bin/codesign";
  signTask.arguments = @[@"-s", self.identityName, @"-f", bundlePath];
  [signTask launch];
  [signTask waitUntilExit];
  return (signTask.terminationStatus == 0);
}

@end
