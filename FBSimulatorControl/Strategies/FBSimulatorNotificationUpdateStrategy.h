/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
