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
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorPool;
@class FBSimulatorSet;

/**
 Options for how a pool should handle allocation & freeing.
 */
typedef NS_OPTIONS(NSUInteger, FBSimulatorAllocationOptions){
  FBSimulatorAllocationOptionsCreate = 1 << 0, /** Permit the creation of Simulators when allocating. */
  FBSimulatorAllocationOptionsReuse = 1 << 1, /** Permit the reuse of Simulators when allocating. */
  FBSimulatorAllocationOptionsShutdownOnAllocate = 1 << 2, /** Shutdown of the Simulator becomes a precondition of allocation. */
  FBSimulatorAllocationOptionsEraseOnAllocate = 1 << 4, /** Erasing of the Simulator becomes a precondition of allocation. */
  FBSimulatorAllocationOptionsDeleteOnFree = 1 << 5, /** Deleting of the Simulator becomes a postcondition of freeing. */
  FBSimulatorAllocationOptionsEraseOnFree = 1 << 6, /** Erasing of the Simulator becomes a postcondition of freeing. */
};

@protocol FBControlCoreLogger;

/**
 A FBSimulatorPool manages the allocation of Simulators from an FBSimulatorSet.
 This is an optional part of the API that allows clients to use multiple Simulators in the same set whilst avoiding
 using the same Simulator for multiple tasks.
 */
@interface FBSimulatorPool : NSObject

#pragma mark Initializers

/**
 Creates and returns an FBSimulatorPool.

 @param set the FBSimulatorSet to Manage.
 @param logger the logger to use to verbosely describe what is going on. May be nil.
 @return a new FBSimulatorPool.
 */
+ (instancetype)poolWithSet:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger;

#pragma mark Methods

/**
 Returns a Device for the given parameters. Will create devices where necessary.
 If you plan on running multiple tests in the lifecycle of a process, you sshould use `freeDevice:error:`
 otherwise devices will continue to be allocated.

 @param configuration the Configuration of the Device to Allocate. Must not be nil.
 @param options the options for the allocation/freeing of the Simulator.
 @return a Future that resovles with the FBSimulator if one could be allocated with the provided options.
 */
- (FBFuture<FBSimulator *> *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration options:(FBSimulatorAllocationOptions)options;

/**
 Marks a device that was previously returned from `allocateDeviceWithName:sdkVersion:error:` as free.
 Call this when multiple test runs, or simulators are to be re-used in a process.

 @param simulator the Simulator to Free.
 @return A future that resolves when freed.
 */
- (FBFuture<NSNull *> *)freeSimulator:(FBSimulator *)simulator;

/**
 Marks a device that was previously returned from `allocateDeviceWithName:sdkVersion:error:` as free.
 Call this when multiple test runs, or simulators are to be re-used in a process.

 @param simulator the Simulator to test.
 @return YES if the Simulator is Allocated, NO otherwise.
 */
- (BOOL)simulatorIsAllocated:(FBSimulator *)simulator;

#pragma mark Properties

/**
 Returns the FBSimulatorSer of the receiver.
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 An Array of all the Simulators that this Pool has allocated.
 */
@property (nonatomic, copy, readonly) NSArray<FBSimulator *> *allocatedSimulators;

/**
 An Array of all the Simulators that this Pool have not allocated.
 */
@property (nonatomic, copy, readonly) NSArray<FBSimulator *> *unallocatedSimulators;

@end

NS_ASSUME_NONNULL_END
