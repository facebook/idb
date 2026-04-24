/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for HealthKit private API.
//
// HKAuthorizationStore is a private XPC client of the healthd daemon
// (mach service com.apple.healthd.server). It is shipped inside the
// public HealthKit.framework but not exposed in the SDK headers, so
// we declare only the methods we use here and call them via the ObjC
// runtime after dlopen-loading HealthKit.framework.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HKHealthStore;

/**
 * XPC client for the healthd daemon. Provides read access to per-bundle
 * HealthKit authorisation records. Created via
 * [[NSClassFromString(@"HKAuthorizationStore") alloc] initWithHealthStore:store]
 * after dlopen of HealthKit.framework.
 */
@interface HKAuthorizationStore : NSObject

- (instancetype)initWithHealthStore:(HKHealthStore *)healthStore;

/**
 * Returns the current authorisation records for a bundle ID. Each
 * record is an opaque ObjC object whose identifying fields (object
 * type, sharing/read status) we read via KVC.
 */
- (void)fetchAuthorizationRecordsForBundleIdentifier:(NSString *)bundleID
                                          completion:(void (^)(NSArray<id> *_Nullable records, NSError *_Nullable error))completion;

/**
 * Resets every authorisation record for the bundle ID back to
 * "not determined". Useful for returning a target app to a clean
 * pre-approval state between test runs.
 */
- (void)resetAuthorizationStatusForBundleIdentifier:(NSString *)bundleID
                                         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
