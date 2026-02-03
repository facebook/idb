/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Used for internal and external implementation.
 */
@protocol FBSimulatorAccessibilityOperations <NSObject>

/**
 Performs an "Accessibility Tap" on the element at the specified point

 @param point the point to tap
 @param expectedLabel if provided, the ax label will be confirmed prior to tapping. In the case of a label mismatch the tap will not proceed
 @return the accessibility element at the point, prior to the tap
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityPerformTapOnElementAtPoint:(CGPoint)point expectedLabel:(nullable NSString *)expectedLabel;

@end


/**
 An Implementation of FBSimulatorAccessibilityCommands.
 */
@interface FBSimulatorAccessibilityCommands : NSObject <FBAccessibilityCommands, FBSimulatorAccessibilityOperations>

@end

NS_ASSUME_NONNULL_END
