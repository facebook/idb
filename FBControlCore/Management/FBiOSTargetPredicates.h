/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetConfiguration.h>
#import <FBControlCore/FBiOSTarget.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTarget;

/**
 NSPredicate instances that operate against FBiOSTarget Objects.
 */
@interface FBiOSTargetPredicates : NSObject

/**
 Predicate for only the provided Simulator. Useful for negation.

 @param target the iOS Target to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)only:(id<FBiOSTarget>)target;

/**
 Predicate for matching against Simulator based on a State.

 @param state the state to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)state:(FBiOSTargetState)state;

/**
 Predicate for matching against Simulator based on a Option Set Target Type.

 @param targetType the Target Type Option Set to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)targetType:(FBiOSTargetType)targetType;

/**
 Predicate for matching against a range of Simulator States.

 @param states An index set of the states to match against.. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)states:(NSIndexSet *)states;

/**
 Predicate for matching against one of multiple Architectures.

 @param architectures the Architectures to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)architectures:(NSArray<NSString *> *)architectures;

/**
 Predicate for matching against one of multiple Names.

 @param names the Names to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)names:(NSArray<NSString *> *)names;

/**
 Predicate for matching against a single Simulator UDID.

 @param udid the UDID to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)udid:(NSString *)udid;

/**
 Predicate for matching against one of multiple Simulator UDIDs.

 @param udids the UDIDs to match against. Must not be nil.
 @return an NSPredicate.
 */
+ (NSPredicate *)udids:(NSArray<NSString *> *)udids;

/**
 Predicate for matching against UDIDs matching a specific target type.

 @param targetType the Target Type Option Set to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)udidsOfType:(FBiOSTargetType)targetType;

/**
 Predicate for matching against many Device Configurations.

 @param deviceConfigurations the Device Configurations to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)devices:(NSArray<FBDeviceModel> *)deviceConfigurations;

/**
 Predicate for matching against many OS Versions.

 @param osVersions the OS Versions to match against.
 @return an NSPredicate.
 */
+ (NSPredicate *)osVersions:(NSArray<FBOSVersionName> *)osVersions;

@end

NS_ASSUME_NONNULL_END
