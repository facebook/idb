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
#import "FBVideoRecordingCommands.h"

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

+ (id<FBInteraction>)launchApplication:(FBApplicationLaunchConfiguration *)configuration command:(id<FBApplicationCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command launchApplication:configuration error:error];
  }];
}

+ (id<FBInteraction>)killApplicationWithBundleID:(NSString *)bundleID command:(id<FBApplicationCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command killApplicationWithBundleID:bundleID error:error];
  }];
}

+ (id<FBInteraction>)startRecordingWithCommand:(id<FBVideoRecordingCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command startRecordingWithError:error];
  }];
}

+ (id<FBInteraction>)stopRecordingWithCommand:(id<FBVideoRecordingCommands>)command
{
  return [FBInteraction interact:^ BOOL (NSError **error) {
    return [command stopRecordingWithError:error];
  }];
}

@end
