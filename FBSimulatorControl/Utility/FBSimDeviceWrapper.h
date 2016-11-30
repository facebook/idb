/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorControlConfiguration;
@class FBSimulatorProcessFetcher;
@class SimDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 Augments methods in CoreSimulator with:
 - More informative return values.
 - Implementations that are more resiliant to failure in CoreSimulator.
 - Annotations of the expected arguments and return types of CoreSimulator.
 */
@interface FBSimDeviceWrapper : NSObject

/**
 Creates a SimDevice Wrapper.

 @param simulator the Simulator to wrap
 @return a new SimDevice wrapper.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

/**
 Installs an Application on the Simulator.
 Will time out with an error if CoreSimulator gets stuck in a semaphore and timeout resiliance is enabled.

 @param appURL the Application URL to use.
 @param options the Options to use in the launch.
 @param error an error out for any error that occured.
 @return YES if the Application was installed successfully, NO otherwise.
 */
- (BOOL)installApplication:(NSURL *)appURL withOptions:(nullable NSDictionary<NSString *, id> *)options error:(NSError **)error;

/**
 Uninstalls an Application on the Simulator.

 @param bundleID the Bundle ID of the Application to uninstall.
 @param options the Options to use in the launch.
 @param error an error out for any error that occured.
 @return YES if the Application was installed successfully, NO otherwise.
 */
- (BOOL)uninstallApplication:(NSString *)bundleID withOptions:(nullable NSDictionary<NSString *, id> *)options error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
