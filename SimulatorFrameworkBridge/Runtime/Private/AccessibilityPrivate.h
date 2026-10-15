/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#define FBAXPathAccessibility "/usr/lib/libAccessibility.dylib"

/** **Borrowed** exported constant; never release the symbol or its pointee. */
typedef CFStringRef const *FBAXAccessibilityNotificationSymbol;
#define FBAXReduceMotionChangedSymbol "kAXSReduceMotionChangedNotification"
#define FBAXReduceTransparencyChangedSymbol "kAXSEnhanceBackgroundContrastChangedNotification"
#define FBAXButtonShapesChangedSymbol "kAXSButtonShapesEnabledNotification"

#define FBAXIncreaseContrastChangedSymbol "kAXSDarkenSystemColorsEnabledNotification"
#define FBAXIncreaseContrastGetSymbol "_AXDarkenSystemColorsGlobal"
typedef BOOL (*FBAXIncreaseContrastGetFn)(void);
