/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBiOSTargetSet.h>

@class FBSimulator;
@class FBSimulatorConfiguration;
@class FBSimulatorControl;
@class FBSimulatorControlConfiguration;
@class SimDeviceSet;

@protocol FBControlCoreLogger;
@protocol FBiOSTargetSetDelegate;

#pragma mark - FBSimulatorSet

/**
 Complements SimDeviceSet with additional functionality and more resiliant behaviours.
 Performs the preconditions necessary to call certain SimDeviceSet/SimDevice methods.
 */
@interface FBSimulatorSet : NSObject <FBiOSTargetSet>

#pragma mark Intializers

/**
 Creates and returns an FBSimulatorSet, performing the preconditions defined in the configuration.

 @param configuration the configuration to use. Must not be nil.
 @param deviceSet the Device Set to wrap.
 @param delegate the delegate notifies of any changes to the state of the simulators in the set
 @param logger the logger to use to verbosely describe what is going on. May be nil.
 @param reporter the event reporter to report to.
 @return a new FBSimulatorSet.
 */
+ (nonnull instancetype)setWithConfiguration:(nonnull FBSimulatorControlConfiguration *)configuration deviceSet:(nonnull SimDeviceSet *)deviceSet delegate:(nullable id<FBiOSTargetSetDelegate>)delegate logger:(nullable id<FBControlCoreLogger>)logger reporter:(nullable id<FBEventReporter>)reporter;

#pragma mark Querying

/**
 Fetches a Simulator matching the specified udid

 @param udid the UDID of the Simulator to fetch.
 @return an FBSimulator instance if one matches the provided udid, else nil
 */
- (nullable FBSimulator *)simulatorWithUDID:(nonnull NSString *)udid;

#pragma mark Creation Methods

/**
 Creates and returns a FBSimulator based on a provided configuration.

 @param configuration the Configuration of the Device to Allocate. Must not be nil.
 @return a Future wrapping a created FBSimulator if one could be created.
 */
- (nonnull FBFuture<FBSimulator *> *)createSimulatorWithConfiguration:(nonnull FBSimulatorConfiguration *)configuration;

/**
 Clones and returns an FBSimulator that is cloned from an existing simulator.

 @param simulator the Simulator to clone.
 @param destinationSet the destination simulator set for the simulator. May be self.
 @return a Future wrapping a created FBSimulator if one could be cloned.
 */
- (nonnull FBFuture<FBSimulator *> *)cloneSimulator:(nonnull FBSimulator *)simulator toDeviceSet:(nonnull FBSimulatorSet *)destinationSet;

/**
 Finds and creates the Configurations for the missing 'Default Simulators' in the receiver.
 */
- (nonnull NSArray<FBSimulatorConfiguration *> *)configurationsForAbsentDefaultSimulators;

#pragma mark Desctructive Methods

/**
 Shuts down a simulator in the set.
 The Set to which the Simulator belongs must be present the receiver.

 @param simulator the Simulator to shutdown. Must not be nil.
 @return an Future that resolves when the operation has completed.
 */
- (nonnull FBFuture<NSNull *> *)shutdown:(nonnull FBSimulator *)simulator;

/**
 Erases a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to erase. Must not be nil.
 @return an Future that resolves when the operation has completed.
 */
- (nonnull FBFuture<NSNull *> *)erase:(nonnull FBSimulator *)simulator;

/**
 Deletes a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to delete. Must not be nil.
 @return A future wrapping the delegate simulators.
 */
- (nonnull FBFuture<NSNull *> *)delete:(nonnull FBSimulator *)simulator;

/**
 Performs a shutdown all of the Simulators that belong to the receiver.

 @return an Future that resolves when successful.
 */
- (nonnull FBFuture<NSNull *> *)shutdownAll;

/**
 Delete all of the Simulators that belong to the receiver.

 @return A future wrapping the erased simulators udids.
 */
- (nonnull FBFuture<NSNull *> *)deleteAll;

/**
 The Logger to use.
 */
@property (nullable, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

/**
 The event reporter to use.
 */
@property (nullable, nonatomic, readonly, strong) id<FBEventReporter> reporter;

/**
 Returns the configuration for the receiver.
 */
@property (nonnull, nonatomic, readonly, copy) FBSimulatorControlConfiguration *configuration;

/**
 The SimDeviceSet to that is owned by the receiver.
 */
@property (nonnull, nonatomic, readonly, strong) SimDeviceSet *deviceSet;

/**
 An NSArray<FBSimulator> of all Simulators in the Set.
*/
@property (nonnull, nonatomic, readonly, copy) NSArray<FBSimulator *> *allSimulators;

/**
 The work queue that will be used by all simulators within the set.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;

/**
 The async queue that will be used by all simulators within the set.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;

@end
