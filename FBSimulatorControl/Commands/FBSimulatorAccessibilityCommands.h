/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands relating to Accessibility.
 */
@protocol FBSimulatorAccessibilityCommands <NSObject, FBiOSTargetCommand>

/**
 The Acessibility Elements.
 Obtain the acessibility elements for the main screen.
 The returned value is fully JSON serializable.

 @return the accessibility elements for the main screen, wrapped in a Future.
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElements;

/**
 Obtain the acessibility element for the main screen at the given point.
 The returned value is fully JSON serializable.

 @param point the coordinate at which to obtain the accessibility element.
 @return the accessibility element at the provided point, wrapped in a Future.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point;

@end

/**
 An Implementation of FBSimulatorAccessibilityCommands.
 */
@interface FBSimulatorAccessibilityCommands : NSObject <FBSimulatorAccessibilityCommands>

@end

NS_ASSUME_NONNULL_END
