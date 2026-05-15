/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 An Implementation of FBSimulatorAccessibilityCommands.
 */
@interface FBSimulatorAccessibilityCommands : NSObject <FBAccessibilityCommands>

// FBiOSTargetCommand (Swift protocol members declared for visibility)
+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target;

// FBAccessibilityCommands (Swift protocol members declared for visibility)
- (nonnull FBFuture<FBAccessibilityElement *> *)accessibilityElementAtPoint:(CGPoint)point;
- (nonnull FBFuture<FBAccessibilityElement *> *)accessibilityElementForFrontmostApplication;

@end
