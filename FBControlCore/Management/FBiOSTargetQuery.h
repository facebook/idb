/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTarget.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBiOSTargetConfiguration.h>
#import <FBControlCore/FBArchitecture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulatorSet;

/**
 A Value representing a way of fetching Simulators.
 */
@interface FBiOSTargetQuery : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

/**
 A Query that matches all iOS Targets.

 @return a new Query matching all Targets.
 */
+ (instancetype)allTargets;

/**
 A Query that matches the given Names.

 @param names the names to match against.
 @return a new Target Query.
 */
+ (instancetype)names:(NSArray<NSString *> *)names;
- (instancetype)names:(NSArray<NSString *> *)names;

/**
 A Query that matches the given Name.

 @param name the name to match against.
 @return a new Target Query.
 */
+ (instancetype)named:(NSString *)name;
- (instancetype)named:(NSString *)name;

/**
 A Query that matches the given UDIDs.

 @param udids the UDIDs to match against.
 @return a new Target Query.
 */
+ (instancetype)udids:(NSArray<NSString *> *)udids;
- (instancetype)udids:(NSArray<NSString *> *)udids;

/**
 A Query that matches the given UDIDs.

 @param udid the UDID to match against.
 @return a new Target Query.
 */
+ (instancetype)udid:(NSString *)udid;
- (instancetype)udid:(NSString *)udid;

/**
 A Query that matches the given States.

 @param states the States to match against, as an NSIndexSet of FBiOSTargetState enums.
 @return a new Target Query.
 */
+ (instancetype)states:(NSIndexSet *)states;
- (instancetype)states:(NSIndexSet *)states;

/**
 A Query that matches the given State.

 @param state the State to match against.
 @return a new Target Query.
 */
+ (instancetype)state:(FBiOSTargetState)state;
- (instancetype)state:(FBiOSTargetState)state;

/**
 A Query that matches the given Architectures.

 @param architectures the Architectures to match against.
 @return a new Target Query.
 */
+ (instancetype)architectures:(NSArray<FBArchitecture> *)architectures;
- (instancetype)architectures:(NSArray<FBArchitecture> *)architectures;

/**
 A Query that matches the given Architecture.

 @param architecture the Architecture to match against.
 @return a new Target Query.
 */
+ (instancetype)architecture:(FBArchitecture)architecture;
- (instancetype)architecture:(FBArchitecture)architecture;

/**
 A Query that matches the given Target Tyep.

 @param targetType the target type to
 @return a new Target Query.
 */
+ (instancetype)targetType:(FBiOSTargetType)targetType;
- (instancetype)targetType:(FBiOSTargetType)targetType;

/**
 A Query that matches the given OS Versions.

 @param osVersions the OS Versions to match against.
 @return a new Target Query.
 */
+ (instancetype)osVersions:(NSArray<FBOSVersionName> *)osVersions;
- (instancetype)osVersions:(NSArray<FBOSVersionName> *)osVersions;

/**
 A Query that matches the given OS Version.

 @param osVersion the OS Version to match against.
 @return a new Target Query.
 */
+ (instancetype)osVersion:(FBOSVersionName)osVersion;
- (instancetype)osVersion:(FBOSVersionName)osVersion;

/**
 A Query that matches the given Device Models.

 @param devices the Device Models to match against.
 @return a new Target Query.
 */
+ (instancetype)devices:(NSArray<FBDeviceModel> *)devices;
- (instancetype)devices:(NSArray<FBDeviceModel> *)devices;

/**
 A Query that matches the given Device Model

 @param device the Device to match against.
 @return a new Target Query.
 */
+ (instancetype)device:(FBDeviceModel)device;
- (instancetype)device:(FBDeviceModel)device;

/**
 A Query that matches the given Range.

 @param range the range to match against.
 @return a new Target Query.
 */
+ (instancetype)range:(NSRange)range;
- (instancetype)range:(NSRange)range;

/**
 Filters iOS Targets based on the reciver.

 @param targets the targets to filter.
 @return a filtered array of targets.
 */
- (NSArray<id<FBiOSTargetInfo>> *)filter:(NSArray<id<FBiOSTargetInfo>> *)targets;

/**
 Determines whether the Query excludes all of a specific target type.

 @param targetType the Target Type to determine whether if it is excluded.
 @return YES if all targets of the given type are excluded from the query, NO otherwise.
 */
- (BOOL)excludesAll:(FBiOSTargetType)targetType;

/**
 The Names to Match against
 An Empty Set means that no Name filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<NSString *> *names;

/**
 The UDIDs to Match against.
 An Empty Set means that no UDID filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<NSString *> *udids;

/**
 The States to match against, coerced from FBiOSTargetState to an NSNumber Representation.
 An Empty Set means that no State filtering will occur.
 */
@property (nonatomic, readonly, copy) NSIndexSet *states;

/**
 The Architectures to Match against.
 An Empty Set means that no Architecture filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<FBArchitecture> *architectures;

/**
 The Target Types to match against.
 FBiOSTargetTypeNone means no Target Type filtering with occur.
 */
@property (nonatomic, readonly, assign) FBiOSTargetType targetType;

/**
 The OS Versions to match against.
 An Empty Set means that no OS Version filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<FBOSVersionName> *osVersions;

/**
 The Device Types to match against.
 An Empty Set means that no Device filtering will occur.
 */
@property (nonatomic, readonly, copy) NSSet<FBDeviceModel> *devices;

/**
 The Range of Simulators to match against when fetched.
 A Location of NSNotFound means that all matching Simulators will be fetched.
 */
@property (nonatomic, readonly, assign) NSRange range;

@end

NS_ASSUME_NONNULL_END
