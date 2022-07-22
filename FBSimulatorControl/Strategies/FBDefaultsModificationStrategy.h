/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 A class for modifying defaults that reside on a Simulator.
 */
@interface FBDefaultsModificationStrategy : NSObject

/**
 A Strategy for modifying a plist.

 @param simulator the Simulator to use.
 @return a new strategy for the Simulator.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Modifies the defaults in a given domain or path.

 @param domainOrPath the domain or path to modify.
 @param defaults key value pair of defaults to set.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)modifyDefaultsInDomainOrPath:(nullable NSString *)domainOrPath defaults:(NSDictionary<NSString *, id> *)defaults;

@end

/**
 Modifies a preference used by Applications
 */
@interface FBPreferenceModificationStrategy : FBDefaultsModificationStrategy

/**
 Sets preference by name and value for a given domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param value preference value
 @param type preference value type. If null defaults to `string`.
 @param domain preference domain - optional
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setPreference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain;
/**
 Gets a preference value by its name and domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param domain domain to search - optional
 @return a Future that resolves with the current preference value
 */
- (FBFuture<NSString *> *)getCurrentPreference:(NSString *)name domain:(nullable NSString *)domain;

@end

/**
 Modifies the defaults for the locationd daemon.
 */
@interface FBLocationServicesModificationStrategy : FBDefaultsModificationStrategy

/**
 Approves Location Services for Applications.

 @param bundleIDs an NSArray<NSString> of bundle IDs to to authorize location settings for.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)approveLocationServicesForBundleIDs:(NSArray<NSString *> *)bundleIDs;

/**
 Revokes Location Services for Applications.

 @param bundleIDs an NSArray<NSString> of bundle IDs to to revoke location settings for.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)revokeLocationServicesForBundleIDs:(NSArray<NSString *> *)bundleIDs;

@end

NS_ASSUME_NONNULL_END
