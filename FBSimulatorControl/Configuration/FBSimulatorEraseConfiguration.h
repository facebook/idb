/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetAction.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for an Log Tail.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeErase;

/**
 An FBiOSTargetAction for Erasing a Simulator.
 */
@interface FBSimulatorEraseConfiguration : FBiOSTargetActionSimple <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
