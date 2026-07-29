/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

// An opaque handle to an accessibility element in the guest. The application
// root is obtained by process identifier and passed to
// `_XCTD_fetchAttributes:forElement:` to walk the tree.
@interface XCAccessibilityElement : NSObject

+ (instancetype)elementWithProcessIdentifier:(int)processIdentifier;

@end
