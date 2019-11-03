/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Applications related to FBSimulatorControl.
 */
@interface FBBundleDescriptor (Simulator)

/**
 Returns the FBBundleDescriptor for the current version of Xcode's Simulator.app.
 Will assert if the FBBundleDescriptor instance could not be constructed.

 @return A FBBundleDescriptor instance for the Simulator.app.
 */
+ (instancetype)xcodeSimulator;

/**
 Returns the System Application with the provided name.

 @param appName the System Application to fetch.
 @param simulator the Simulator to fetch for.
 @param error any error that occurred in fetching the application.
 @return FBBundleDescriptor instance if one could for the given name could be found, nil otherwise.
 */
+ (nullable instancetype)systemApplicationNamed:(NSString *)appName simulator:(FBSimulator *)simulator error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
