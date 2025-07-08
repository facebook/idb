/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

@protocol FBSimulatorApplicationCommands <NSObject>

/**
 Returns the Installed Application Info associated with the given Bundle ID
 
 @param bundleID the Bundle ID to fetch for
 @param error an error out for any error that occurws
 @return the FBInstalledApplication if successful, nil on failure
 */
- (nullable FBInstalledApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

@end

/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBApplicationCommands, FBSimulatorApplicationCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
