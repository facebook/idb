/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBDeltaUpdateManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef FBDeltaUpdateManager<NSString *, id<FBiOSTargetContinuation>, NSNull *> FBVideoUpdateManager;

/**
 Manages the Video state for an IDB Companion.
 */
@interface FBDeltaUpdateManager (Video)

#pragma mark Initializers

/**
 Makes a Video Manager for the provided target.

 @param target the target to use.
 */
+ (FBVideoUpdateManager *)videoManagerForTarget:(id<FBiOSTarget>)target;

@end

NS_ASSUME_NONNULL_END
