/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBDeltaUpdateManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef FBDeltaUpdateManager<NSData *, id<FBLogOperation>, NSArray<NSString *> *> FBLogUpdateManager;

/**
 A container for log sessions.
 */
@interface FBDeltaUpdateManager (Log)

#pragma mark Public Methods

/**
 A manager of log updates
 */
+ (FBLogUpdateManager *)logManagerWithTarget:(id<FBiOSTarget>)target;

@end

NS_ASSUME_NONNULL_END
