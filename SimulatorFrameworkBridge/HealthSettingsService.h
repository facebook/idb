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
 * - "approve" — set status = share+read authorised for the listed
 *   types (or a curated default set when none given). Seeds the
 *   request record first; safe to call before any app-side
 *   `requestAuthorization`.
 *
 * Returns 0 on success, non-zero on failure (HealthKit framework load
 * failure, missing entitlements, XPC error, etc.).
 */
int handleHealthSettingsAction(NSString *action,
                               NSString *bundleID,
                               NSArray<NSString *> *typeIdentifiers);
