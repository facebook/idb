/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager+Video.h"

#import "FBIDBError.h"

@implementation FBDeltaUpdateManager (Video)

#pragma mark Initializers

+ (FBVideoUpdateManager *)videoManagerForTarget:(id<FBiOSTarget>)target
{
  NSString *videoFilePath = [[target.auxillaryDirectory stringByAppendingPathComponent:@"idb_encode"] stringByAppendingPathExtension:@"mp4"];
  return [self
    managerWithTarget:target
    name:@"video"
    expiration:nil
    capacity:@1
    logger:target.logger
    create:^(id _) {
      return [target startRecordingToFile:videoFilePath];
    }
    delta:^(id<FBiOSTargetContinuation> operation, NSString *identifier, BOOL *done) {
      return [FBFuture futureWithResult:videoFilePath];
    }];
}

@end
