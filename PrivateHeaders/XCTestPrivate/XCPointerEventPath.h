/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// A single pointer's path through a synthesized event: press down, optional
// moves, lift up. Offsets are seconds relative to the start of the event.
@interface XCPointerEventPath : NSObject

- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)pressDownAtOffset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;

@end
