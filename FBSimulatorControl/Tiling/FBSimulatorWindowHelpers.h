/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class FBSimulator;

/**
 Helpers for obtaining information about Application Windows.
 */
@interface FBSimulatorWindowHelpers : NSObject

/**
 Creates and returns an NSArray<CGRect> of the bounds of all Simulators except the provided Simulator.

 @param simulator simulator to exclude from the bounds fetch
 @return an NSArray<CGRect> of these bounds.
 */
+ (NSArray *)obtainBoundsOfOtherSimulators:(FBSimulator *)simulator;

/**
 Creates and returns an NSArray<NSDictionary> of Simulator.app Windows that belong to the Ordered Set of Simulator.
 The Dictionary contains Windows in format from 'Quartz Window Services'

 @param simulators the array of Simulators to find Windows For.
 @return array an Array of the windows that could be found for the provided Simulators.
 */
+ (NSArray *)windowsForSimulators:(NSArray *)simulators;

/**
 Returns the CGDirectDisplayID for the provided Simulator.

 @param simulator the Simulators to find the DisplayID For.
 @param cropRect an outparam for the Cropping Rectangle in Screen Bounds.
 @param screenSize the size of the Screen containing the Simulator.
 @return the Display ID of the Simulator or 0 if it could not be found.
 */
+ (CGDirectDisplayID)displayIDForSimulator:(FBSimulator *)simulator cropRect:(CGRect *)cropRect screenSize:(CGSize *)screenSize;

/**
 Returns a String representing the known information about Simulator Windows as well as the Diplays.
 This can be helpful when you wish to know about the working environment of a CI machine.
 */
+ (NSString *)debugDescription;

@end
