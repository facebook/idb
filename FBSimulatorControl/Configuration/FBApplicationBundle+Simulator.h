/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Applications related to FBSimulatorControl.
 */
@interface FBApplicationBundle (Simulator)

/**
 Returns the FBApplicationBundle for the current version of Xcode's Simulator.app.
 Will assert if the FBApplicationBundle instance could not be constructed.

 @return A FBApplicationBundle instance for the Simulator.app.
 */
+ (instancetype)xcodeSimulator;

/**
 Returns the System Application with the provided name.

 @param appName the System Application to fetch.
 @param simulator the Simulator to fetch for.
 @param error any error that occurred in fetching the application.
 @return FBApplicationBundle instance if one could for the given name could be found, nil otherwise.
 */
+ (nullable instancetype)systemApplicationNamed:(NSString *)appName simulator:(FBSimulator *)simulator error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
