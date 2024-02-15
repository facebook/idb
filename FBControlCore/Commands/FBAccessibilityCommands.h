/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Used for internal and external implementation.
 */
@protocol FBAccessibilityOperations <NSObject>

/**
 The Acessibility Elements.
 Obtain the acessibility elements for the main screen.
 The returned value is fully JSON serializable.

 @param nestedFormat if YES then data is returned in the nested format, NO for flat format
 @return the accessibility elements for the main screen, wrapped in a Future.
 */
- (FBFuture<id> *)accessibilityElementsWithNestedFormat:(BOOL)nestedFormat;

/**
 Obtain the acessibility element for the main screen at the given point.
 The returned value is fully JSON serializable.

 @param point the coordinate at which to obtain the accessibility element.
 @param nestedFormat if YES then data is returned in the nested format, NO for flat format
 @return the accessibility element at the provided point, wrapped in a Future.
 */
- (FBFuture<id> *)accessibilityElementAtPoint:(CGPoint)point nestedFormat:(BOOL)nestedFormat;

@end


/**
 Commands relating to Accessibility.
 */
@protocol FBAccessibilityCommands <NSObject, FBiOSTargetCommand, FBAccessibilityOperations>

@end

NS_ASSUME_NONNULL_END
