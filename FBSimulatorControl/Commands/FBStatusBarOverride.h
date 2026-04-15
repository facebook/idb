/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Represents a set of status bar overrides for deterministic screenshots.
 Non-nil NSNumber properties are applied as overrides; nil properties are left unchanged.
 All SimDevice status bar methods use raw NSInteger parameters (same as appearance/content size).
 */
@interface FBStatusBarOverride : NSObject

/** Display time string, e.g. @"9:41". */
@property (nullable, nonatomic, copy) NSString *timeString;

/** Data network type. */
@property (nullable, nonatomic, strong) NSNumber *dataNetworkType;

/** WiFi mode: 1=searching, 2=failed, 3=active. */
@property (nullable, nonatomic, strong) NSNumber *wiFiMode;

/** WiFi signal bars (0-3). */
@property (nullable, nonatomic, strong) NSNumber *wiFiBars;

/** Cellular mode: 0=notSupported, 1=searching, 2=failed, 3=active. */
@property (nullable, nonatomic, strong) NSNumber *cellularMode;

/** Cellular signal bars (0-4). */
@property (nullable, nonatomic, strong) NSNumber *cellularBars;

/** Cellular operator name. */
@property (nullable, nonatomic, copy) NSString *operatorName;

/** Battery state. */
@property (nullable, nonatomic, strong) NSNumber *batteryState;

/** Battery level (0-100). */
@property (nullable, nonatomic, strong) NSNumber *batteryLevel;

/** Whether to show "not charging" indicator. */
@property (nullable, nonatomic, strong) NSNumber *showNotCharging;

@end

NS_ASSUME_NONNULL_END
