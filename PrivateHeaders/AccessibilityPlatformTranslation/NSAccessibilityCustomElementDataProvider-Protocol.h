/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NSObject.h"

@class NSData;

@protocol NSAccessibilityCustomElementDataProvider <NSObject>
+ (id)elementWithAccessibilityCustomElementData:(NSData *)arg1;
- (NSData *)accessibilityCustomElementData;

@optional
- (BOOL)overridePresenterPid:(int *)arg1;
- (BOOL)overrideElementPid:(int *)arg1;
@end

