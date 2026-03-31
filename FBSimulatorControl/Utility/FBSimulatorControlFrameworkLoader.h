/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 A Class for handling Framework Loading of Private Frameworks that FBSimulatorControl depends on.
 */
@interface FBSimulatorControlFrameworkLoader : FBControlCoreFrameworkLoader

/**
 The Frameworks needed for most operations.
 */
@property (class, nonnull, nonatomic, readonly, strong) FBSimulatorControlFrameworkLoader *essentialFrameworks;

/**
 The frameworks needed for Accessibility operations.
 */
@property (class, nonnull, nonatomic, readonly, strong) FBSimulatorControlFrameworkLoader *accessibilityFrameworks;

/**
 All of the Frameworks for operations involving the HID and Framebuffer.
 */
@property (class, nonnull, nonatomic, readonly, strong) FBSimulatorControlFrameworkLoader *xcodeFrameworks;

@end
