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
 A Typedef for a SimDevice Callback.
 */
typedef void (^FBSimDeviceWrapperCallback)(void);

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
 @param processFetcher the Process Query to obtain process information.
 @return a new SimDevice wrapper.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator processFetcher:(FBSimulatorProcessFetcher *)processFetcher;

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

/**
 Spawns an long-lived executable on the Simulator.
 The Task should not terminate in less than a few seconds, as Process Info will be obtained.

 @param launchPath the path to the binary.
 @param options the Options to use in the launch.
 @param terminationHandler a Termination Handler for when the process dies.
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, nil otherwise.
 */
- (nullable FBProcessInfo *)spawnLongRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options terminationHandler:(nullable FBSimDeviceWrapperCallback)terminationHandler error:(NSError **)error;

/**
 Spawns an short-lived executable on the Simulator.
 The Process Identifier of the task will be returned, but will be invalid by the time it is returned if the process is short-lived.
 Will block for timeout seconds to confirm that the process terminates

 @param launchPath the path to the binary.
 @param options the Options to use in the launch.
 @param timeout the number of seconds to wait for the process to terminate.
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, -1 otherwise.
 */
- (pid_t)spawnShortRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options timeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
