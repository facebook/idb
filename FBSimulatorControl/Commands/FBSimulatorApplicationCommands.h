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

@class FBSimulator;
@class FBSimulatorApplicationOperation;

/**
 Simulator-Specific Application Commands.
 */
@protocol FBSimulatorApplicationCommands <FBApplicationCommands, FBiOSTargetCommand>

#pragma mark Querying Application State

/**
 Determines the location of the Data Container of an Application, it's chroot jail.

 @param bundleID the Bundle ID of the Application to search for,.
 @note returns absolute path
 @return a Future with the home directory.
 */
- (FBFuture<NSString *> *)dataContainerOfApplicationWithBundleID:(NSString *)bundleID;

/**
 Returns the Process Info for a Application by Bundle ID.

 @param bundleID the Bundle ID to fetch an installed application for.
 @return A future that resolves with the process info of the running application.
 */
- (FBFuture<FBProcessInfo *> *)runningApplicationWithBundleID:(NSString *)bundleID;

@end

/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBSimulatorApplicationCommands>

@end

NS_ASSUME_NONNULL_END
