/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
@class FBSimulatorProcessFetcher;
@class FBiOSTargetQuery;
@class SimDeviceSet;

@protocol FBControlCoreLogger;
@protocol FBiOSTargetSetDelegate;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - FBSimulatorSet

/**
 Complements SimDeviceSet with additional functionality and more resiliant behaviours.
 Performs the preconditions necessary to call certain SimDeviceSet/SimDevice methods.
 */
@interface FBSimulatorSet : NSObject <FBDebugDescribeable, FBJSONSerializable, FBiOSTargetSet>

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
 Fetches the Simulators from the Set, matching the query.

 @param query the Query to query with.
 @return an array of matching Simulators.
 */
- (NSArray<FBSimulator *> *)query:(FBiOSTargetQuery *)query;

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
 Kills a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to delete. Must not be nil.
 @return an Future that resolves when successful.
 */
- (FBFuture<FBSimulator *> *)killSimulator:(FBSimulator *)simulator;

/**
 Erases a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to erase. Must not be nil.
 @return A future wrapping the erased simulators udids.
 */
- (FBFuture<FBSimulator *> *)eraseSimulator:(FBSimulator *)simulator;

/**
 Deletes a Simulator in the Set.
 The Set to which the Simulator belongs must be the receiver.

 @param simulator the Simulator to delete. Must not be nil.
 @return A future wrapping the delegate simulators.
 */
- (FBFuture<NSString *> *)deleteSimulator:(FBSimulator *)simulator;

/**
 Kills all provided Simulators.
 The Set to which the Simulators belong must be the receiver.

 @param simulators the Simulators to kill. Must not be nil.
 @return an Future that resolves when successful.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)killAll:(NSArray<FBSimulator *> *)simulators;

/**
 Erases all provided Simulators.
 The Set to which the Simulators belong must be the receiver.

 @param simulators the Simulators to erase. Must not be nil.
 @return A future wrapping the erased simulators.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)eraseAll:(NSArray<FBSimulator *> *)simulators;

/**
 Erases all provided Simulators.
 The Set to which the Simulators belong must be the receiver.

 @param simulators the Simulators to delete. Must not be nil.
 @return A future wrapping the erased simulators udids.
 */
- (FBFuture<NSArray<NSString *> *> *)deleteAll:(NSArray<FBSimulator *> *)simulators;

/**
 Kills all of the Simulators that belong to the receiver.

 @return an Future that resolves when successful.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)killAll;

/**
 Kills all of the Simulators that belong to the receiver.

 @return A future wrapping the erased simulators.
 */
- (FBFuture<NSArray<FBSimulator *> *> *)eraseAll;

/**
 Delete all of the Simulators that belong to the receiver.

 @return A future wrapping the erased simulators udids.
 */
- (FBFuture<NSArray<NSString *> *> *)deleteAll;

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
 The FBProcessFetcher that is used to obtain Simulator Process Information.
 */
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

/**
 An NSArray<FBSimulator> of all Simulators in the Set.
*/
@property (nonatomic, copy, readonly) NSArray<FBSimulator *> *allSimulators;

@end

NS_ASSUME_NONNULL_END
