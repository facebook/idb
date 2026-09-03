/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the AccessibilityUtilities private API used to control the simulator's
// device-wide accessibility automation mode. The framework is loaded dynamically and the class is
// resolved by name, so these declarations provide compile-time message signatures without creating
// link-time class references.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define FBAXPathAccessibilityUtilities \
        "/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities"

@class AXSettings;

@protocol AXSettingsClass <NSObject>
+ (nullable AXSettings *)sharedInstance;
@end

@interface AXSettings : NSObject
- (void)setAutomationEnabled:(BOOL)enabled;
@end

NS_ASSUME_NONNULL_END
