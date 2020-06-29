/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class NSString;

@protocol NSAccessibilityElement <NSObject>
- (id)accessibilityParent;
- (struct CGRect)accessibilityFrame;

@optional
- (NSString *)accessibilityIdentifier;
- (BOOL)isAccessibilityFocused;
@end

