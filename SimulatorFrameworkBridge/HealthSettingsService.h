/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Entry point for the HealthKit authorisation service.
 *
 * Verbs:
 * - "list" — print authorisation records for `bundleID` as JSON.
 * - "clear" — reset every authorisation record for `bundleID` back
 *   to NotDetermined.
 *
 * Returns 0 on success, non-zero on failure (HealthKit framework load
 * failure, missing entitlements, XPC error, etc.).
 *
 * `typeIdentifiers` is currently unused but reserved for future verbs
 * (`approve`, `revoke`) that operate on per-type subsets.
 */
int handleHealthSettingsAction(NSString *action,
                               NSString *bundleID,
                               NSArray<NSString *> *typeIdentifiers);
