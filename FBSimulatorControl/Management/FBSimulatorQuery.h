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
#import <FBSimulatorControl/FBSimulatorConfigurationVariants.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulatorSet;

/**
 A Value representing a way of fetching Simulators.
 */
@interface FBSimulatorQuery : NSObject <NSCopying, NSCoding, FBJSONSerializable, FBJSONDeserializable>

/**
 A Query that matches all Simulators.

 @return a new Simulator Query.
 */
+ (instancetype)allSimulators;

/**
 A Query that matches the given UDIDs.

 @param udids the UDIDs to match against.
 @return a new Simulator Query.
 */
+ (instancetype)udids:(NSArray<NSString *> *)udids;
- (instancetype)udids:(NSArray<NSString *> *)udids;

/**
 A Query that matches the given States.

 @param states the UDIDs to match against.
 @return a new Simulator Query.
 */
+ (instancetype)states:(NSArray<NSNumber *> *)states;
- (instancetype)states:(NSArray<NSNumber *> *)states;

/**
 A Query that matches the given OS Versions.

 @param osVersions the OS Versions to match against.
 @return a new Simulator Query.
 */
+ (instancetype)osVersions:(NSArray<id<FBSimulatorConfiguration_OS>> *)osVersions;
- (instancetype)osVersions:(NSArray<id<FBSimulatorConfiguration_OS>> *)osVersions;

/**
 A Query that matches the given Devices.

 @param devices the Devices to match against.
 @return a new Simulator Query.
 */
+ (instancetype)devices:(NSArray<id<FBSimulatorConfiguration_Device>> *)devices;
- (instancetype)devices:(NSArray<id<FBSimulatorConfiguration_Device>> *)devices;

/**
 A Query that matches the given Range.

 @param range the range to match against.
 @return a new Simulator Query.
 */
+ (instancetype)range:(NSRange)range;
- (instancetype)range:(NSRange)range;

/**
 The UDIDs to Match against.
 An Empty Set means that no UDID filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<NSString *> *udids;

/**
 The States to match against, coerced from FBSimulatorState to an NSNumber Representation.
 An Empty Set means that no State filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *states;

/**
 The OS Versions to match against.
 An Empty Set means that no OS Version filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<id<FBSimulatorConfiguration_OS>> *osVersions;

/**
 The Device Types to match against.
 An Empty Set means that no Device filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<id<FBSimulatorConfiguration_Device>> *devices;

/**
 The Range of Simulators to match against when fetched.
 A Location of NSNotFound means that all matching Simulators will be fetched.
 */
@property (nonatomic, readonly, assign) NSRange range;

/**
 Returns the Simulators in the Set, matching against the query.

 @param set the Set to perform against.
 @return an Array of the Matching Simulators.
 */
- (NSArray<FBSimulator *> *)perform:(FBSimulatorSet *)set;

@end

NS_ASSUME_NONNULL_END
