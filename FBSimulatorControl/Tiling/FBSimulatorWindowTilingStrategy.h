/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;

/**
 A Protocol for defining a Strategy of the placement of Simulator Windows within the host's display.
 */
@protocol FBSimulatorWindowTilingStrategy <NSObject>

/**
 Returns the best position for a window.

 @param windowSize the Size of the Window to place.
 @param error an Error out for any error that occurred.
 @return the target position of the rectangle, or CGRectNull if there is no possible placement for the Window.s
 */
- (CGRect)targetPositionOfWindowWithSize:(CGSize)windowSize inScreenSize:(CGSize)screenSize withError:(NSError **)error;

@end

/**
 Implementations of Tiling Strategy
 */
@interface FBSimulatorWindowTilingStrategy : NSObject

/**
 A Strategy that tiles windows horizontally based on the presence of occluding Simulators, determined by the existence of Simulators other than the 'target'.

 @param targetSimulator the existing Simulator to place. Simulators other than the 'targetSimulator' will be considered occluded areas.
 @return a Window Tiling Strategy
 */
+ (id<FBSimulatorWindowTilingStrategy>)horizontalOcclusionStrategy:(FBSimulator *)targetSimulator;

/**
 A Strategy that tiles windows horizontally based on a offset in a horizontally divided screen.

 @param offset the offset
 @param total the total number of offsets
 @return a Window Tiling Strategy
 */
+ (id<FBSimulatorWindowTilingStrategy>)isolatedRegionStrategyWithOffset:(NSInteger)offset total:(NSInteger)total;

@end
