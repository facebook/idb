/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 Modifies the Apple Locale used by Applications
 */
@interface FBLocaleModificationStrategy : FBDefaultsModificationStrategy

/**
 Sets the Locale, by Locale Identifier

 @param localeIdentifier the locale identifier.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setLocaleWithIdentifier:(NSString *)localeIdentifier;

/**
 Gets the Locale, by Locale Identifier

 @return a Future that resolves with the current locale identifier.
 */
- (FBFuture<NSString *> *)getCurrentLocaleIdentifier;

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

@end

NS_ASSUME_NONNULL_END
