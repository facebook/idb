/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AccessibilityPlatformTranslation/NSObject.h>

@class NSAccessibilityCustomRotor, NSAccessibilityCustomRotorItemResult, NSAccessibilityCustomRotorSearchParameters;

@protocol NSAccessibilityCustomRotorItemSearchDelegate <NSObject>
- (NSAccessibilityCustomRotorItemResult *)rotor:(NSAccessibilityCustomRotor *)arg1 resultForSearchParameters:(NSAccessibilityCustomRotorSearchParameters *)arg2;
@end

