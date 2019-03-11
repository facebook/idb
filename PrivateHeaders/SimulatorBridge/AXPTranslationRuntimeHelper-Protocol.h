/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class AXPTranslationObject;

@protocol AXPTranslationRuntimeHelper <NSObject>

@optional

- (void)handleNotification:(unsigned long long)arg1 data:(id<NSObject, NSCopying, NSSecureCoding>)arg2 associatedObject:(AXPTranslationObject *)arg3;

@end

