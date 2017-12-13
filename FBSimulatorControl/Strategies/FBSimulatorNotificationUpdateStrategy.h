/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulatorSet;

/**
 A Strategy that responds to updates of Simulator States.
 */
@interface FBSimulatorNotificationUpdateStrategy : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param set the Simulator Set to use.
 @return a new Strategy
 */
+ (instancetype)strategyWithSet:(FBSimulatorSet *)set;

@end

NS_ASSUME_NONNULL_END
