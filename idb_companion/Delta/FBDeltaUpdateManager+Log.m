/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager+Log.h"

#import "FBIDBError.h"

NSTimeInterval const FBLogSessionTimeout = 60.0;

@implementation FBDeltaUpdateManager (Log)

+ (FBLogUpdateManager *)logManagerWithTarget:(id<FBiOSTarget>)target
{
  return [self
    managerWithTarget:target
    name:@"log"
    expiration:@(FBLogSessionTimeout)
    capacity:nil
    logger:target.logger
    create:^ FBFuture<id<FBLogOperation>> * (NSArray<NSString *> *arguments) {
      id<FBConsumableBuffer> lineBuffer = FBDataBuffer.consumableBuffer;
      return [target tailLog:arguments consumer:lineBuffer];
    }
    delta:^ FBFuture<NSData *> * (id<FBLogOperation> operation, NSString *identifier, BOOL *done) {
      id<FBConsumableBuffer> lineBuffer = (id<FBConsumableBuffer>) operation.consumer;
      NSData *data = [lineBuffer consumeCurrentData];
      return [FBFuture futureWithResult:data];
    }];
}

@end
