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
 * `options` is a bitmask, **not an object** — both runtimes encode it
 * as `Q`. It was declared here as an `NSDictionary *` for a long time;
 * the only caller passed nil, which marshals as 0, so the mistake never
 * surfaced. Zero is the value the Health-app UI passes.
 *
 * Prerequisite: a matching `setRequestedAuthorizationForBundleIdentifier:`
 * call must have created an authorisation request for each (bundleID,
 * type) pair, otherwise the row is silently dropped on the daemon side.
 *
 * **This is the iOS 26.x spelling.** iOS 27 renamed it to the
 * `modeInfos:` variant below. Exactly one of the two is present on any
 * given runtime, so a caller must ask with `respondsToSelector:` and
 * send whichever answers — see `HealthSettingsService`.
 *
 * Encoding on iOS 26.5 (23F77): `v56@0:8@16@24@32Q40@?48`.
 */
- (void)setAuthorizationStatuses:(NSDictionary<HKObjectType *, NSNumber *> *)statuses
              authorizationModes:(NSDictionary<HKObjectType *, NSNumber *> *)modes
             forBundleIdentifier:(NSString *)bundleID
                         options:(NSUInteger)options
                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/**
 * The iOS 27 spelling of the method above, taking an extra `modeInfos:`
 * dictionary between the modes and the bundle identifier. Passing an
 * empty dictionary matches what the Health-app UI does, the same way an
 * empty `modes` does.
 *
 * Encoding on iOS 27.0 (24A5390f): `v64@0:8@16@24@32@40Q48@?56`.
 */
- (void)setAuthorizationStatuses:(NSDictionary<HKObjectType *, NSNumber *> *)statuses
              authorizationModes:(NSDictionary<HKObjectType *, NSNumber *> *)modes
                       modeInfos:(NSDictionary *)modeInfos
             forBundleIdentifier:(NSString *)bundleID
                         options:(NSUInteger)options
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
