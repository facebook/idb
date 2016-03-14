// Copyright 2004-present Facebook. All Rights Reserved.

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
