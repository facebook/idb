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

@class HKHealthStore, HKObjectType;

/**
 * XPC client for the healthd daemon. Provides read/write access to
 * per-bundle HealthKit authorisation records. Created via
 * [[NSClassFromString(@"HKAuthorizationStore") alloc] initWithHealthStore:store]
 * after dlopen of HealthKit.framework.
 */
@interface HKAuthorizationStore : NSObject

- (instancetype)initWithHealthStore:(HKHealthStore *)healthStore;

/**
 * Sets per-type authorisation status for a bundle ID. The `statuses`
 * dictionary is keyed by HKObjectType with NSNumber values using the
 * internal HKInternalAuthorizationStatus encoding (NOT the public
 * HKAuthorizationStatus enum):
 *   100 = NotDetermined
 *   101 = share + read authorized
 *   102 = read only (share denied)
 *   103 = share only (read denied)
 *   104 = share + read denied
 *
 * The `modes` dictionary may be empty; healthd looks up the matching
 * authorisation request entries from its database. The Health-app
 * UI always passes an empty modes dict.
 *
 * Prerequisite: a matching `setRequestedAuthorizationForBundleIdentifier:`
 * call must have created an authorisation request for each (bundleID,
 * type) pair, otherwise the row is silently dropped on the daemon side.
 */
- (void)setAuthorizationStatuses:(NSDictionary<HKObjectType *, NSNumber *> *)statuses
              authorizationModes:(NSDictionary<HKObjectType *, NSNumber *> *)modes
             forBundleIdentifier:(NSString *)bundleID
                         options:(nullable NSDictionary *)options
                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/**
 * Seeds an authorisation request record for a bundle ID. Required
 * before `setAuthorizationStatuses:` will write status rows for the
 * given (bundleID, type) pairs (analogous to how an app's first
 * `requestAuthorization` call creates the request entries).
 */
- (void)setRequestedAuthorizationForBundleIdentifier:(NSString *)bundleID
                                          shareTypes:(NSSet<HKObjectType *> *)shareTypes
                                           readTypes:(NSSet<HKObjectType *> *)readTypes
                                          completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

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
