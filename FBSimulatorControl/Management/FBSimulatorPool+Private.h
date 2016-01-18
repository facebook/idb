/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorPool.h>

@class FBProcessQuery;

@interface FBSimulatorPool ()

@property (nonatomic, strong, readonly) SimDeviceSet *deviceSet;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;

@property (nonatomic, strong, readonly) NSMutableOrderedSet *allocatedUDIDs;
@property (nonatomic, strong, readonly) NSMutableDictionary *allocationOptions;
@property (nonatomic, strong, readonly) NSMutableDictionary *inflatedSimulators;

@property (nonatomic, copy, readwrite) NSError *firstRunError;

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet logger:(id<FBSimulatorLogger>)logger;

/**
 Deletes a Simulator in the Pool.

 @param simulator the Simulator to delete.
 @param error an error out for any error that occurs.
 @return an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (BOOL)deleteSimulator:(FBSimulator *)simulator withError:(NSError **)error;

/**
 Kills all of the Simulators the reciever's Device Set.

 @param error an error out if any error occured.
 @return an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killAllWithError:(NSError **)error;

/**
 Delete all of the Simulators Managed by this Pool, killing them first.

 @param error an error out if any error occured.
 @return an Array of the names of the Simulators that were deleted if successful, nil otherwise.
 */
- (NSArray *)deleteAllWithError:(NSError **)error;

@end
