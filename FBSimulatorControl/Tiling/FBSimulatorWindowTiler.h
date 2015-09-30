/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@class FBSimulator;
@protocol FBSimulatorWindowTilingStrategy;

/**
 A Class responsible for tiling Simulator Windows and bringing them to the foreground.
 Tiling differes from 'calculating layout' in the traditional sense since it's undesirable to re-align Windows that have already been placed.
 Keeping a Simulator in the same position since it's first placement means that cropping a recorded video becomes trivial.
 */
@interface FBSimulatorWindowTiler : NSObject

/**
 Creates and returns a new Window Tiler for the provided Simulator
 
 @param simulator the Simulator to position.
 @param strategy the Strategy to use for determining the position of Windows.s
 @return a new FBWindowTiler instance.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator strategy:(id<FBSimulatorWindowTilingStrategy>)strategy;

/**
 Moves the Simuator into the foreground in the first available position that is not occluded by any other Simulator
 If the Window is too small then to contain this, as well as other Simulators, the position is undefined
 
 @param error an error out for any error that occurred.
 @return a CGRect representing the final position of the Window. CGRectNull if an error occured.
 */
- (CGRect)placeInForegroundWithError:(NSError **)error;

@end
