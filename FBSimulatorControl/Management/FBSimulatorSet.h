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

NS_ASSUME_NONNULL_BEGIN

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
 @param error any error that occurred during the creation of the pool.
 @return a new FBSimulatorSet.
 */
+ (instancetype)setWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet delegate:(nullable id<FBiOSTargetSetDelegate>)delegate logger:(nullable id<FBControlCoreLogger>)logger reporter:(nullable id<FBEventReporter>)reporter error:(NSError **)error;

#pragma mark Querying

/**
 Fetches a Simulator matching the specified udid

 @param udid the UDID of the Simulator to fetch.
 @return an FBSimulator instance if one matches the provided udid, else nil
 */
- (nullable FBSimulator *)simulatorWithUDID:(NSString *)udid;

#pragma mark Creation Methods

/**
 Creates and returns a FBSimulator based on a provided configuration.

 @param configuration the Configuration of the Device to Allocate. Must not be nil.
 @return a Future wrapping a created FBSimulator if one could be created.
 */
- (FBFuture<FBSimulator *> *)createSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration;

/**
 Clones and returns an FBSimulator that is cloned from an existing simulator.

 @param simulator the Simulator to clone.
 @param destinationSet the destination simulator set for the simulator. May be self.
 @return a Future wrapping a created FBSimulator if one could be cloned.
 */
- (FBFuture<FBSimulator *> *)cloneSimulator:(FBSimulator *)simulator toDeviceSet:(FBSimulatorSet *)destinationSet;

/**
 Finds and creates the Configurations for the missing 'Default Simulators' in the receiver.
 */
- (NSArray<FBSimulatorConfiguration *> *)configurationsForAbsentDefaultSimulators;

#pragma mark Desctructive Methods

/**
 Shuts down a simulator in the set.
 The Set to which the Simulator belongs must be present the receiver.

 @param simulator the Simulator to shutdown. Must not be nil.
 @return an Future that resolves when the operation has completed.
 */
- (FBFuture<NSNull *> *)shutdown:(FBSimulator *)simulator;

/**
 Erases a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to erase. Must not be nil.
 @return an Future that resolves when the operation has completed.
 */
- (FBFuture<NSNull *> *)erase:(FBSimulator *)simulator;

/**
 Deletes a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to delete. Must not be nil.
 @return A future wrapping the delegate simulators.
 */
- (FBFuture<NSNull *> *)delete:(FBSimulator *)simulator;

/**
 Performs a shutdown all of the Simulators that belong to the receiver.

 @return an Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)shutdownAll;

/**
 Delete all of the Simulators that belong to the receiver.

 @return A future wrapping the erased simulators udids.
 */
- (FBFuture<NSNull *> *)deleteAll;

/**
 The Logger to use.
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The event reporter to use.
 */
@property (nonatomic, strong, nullable, readonly) id<FBEventReporter> reporter;

/**
 Returns the configuration for the receiver.
 */
@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;

/**
 The SimDeviceSet to that is owned by the receiver.
 */
@property (nonatomic, strong, readonly) SimDeviceSet *deviceSet;

/**
 An NSArray<FBSimulator> of all Simulators in the Set.
*/
@property (nonatomic, copy, readonly) NSArray<FBSimulator *> *allSimulators;

/**
 The work queue that will be used by all simulators within the set.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

/**
 The async queue that will be used by all simulators within the set.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

@end

NS_ASSUME_NONNULL_END
