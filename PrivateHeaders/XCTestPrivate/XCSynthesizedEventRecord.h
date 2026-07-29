/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCPointerEventPath;

// A synthesized input event, composed of one or more pointer paths, submitted
// to the guest daemon via `_XCTD_synthesizeEvent:implicitConfirmationInterval:`.
@interface XCSynthesizedEventRecord : NSObject

- (instancetype)initWithName:(NSString *)name displayID:(unsigned int)displayID interfaceOrientation:(long long)interfaceOrientation;
- (void)addPointerEventPath:(XCPointerEventPath *)path;

@end
