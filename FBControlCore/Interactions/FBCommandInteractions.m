/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCommandInteractions.h"

#import "FBApplicationCommands.h"

@implementation FBCommandInteractions

+ (id<FBInteraction>)installApplicationWithPath:(NSString *)path command:(id<FBApplicationCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command installApplicationWithPath:path error:error];
  }];
}

+ (id<FBInteraction>)isApplicationInstalledWithBundleID:(NSString *)bundleID command:(id<FBApplicationCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command isApplicationInstalledWithBundleID:bundleID error:error];
  }];
}

@end
