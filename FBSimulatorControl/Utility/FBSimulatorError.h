/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCoreError.h>

@class FBSimulator;

/**
 The Error Domain for FBSimulatorControl.
 */
extern NSString * _Nonnull const FBSimulatorControlErrorDomain;

/**
 Helpers for constructing Errors representing errors in FBSimulatorControl & adding additional diagnosis.
 */
@interface FBSimulatorError : FBControlCoreError

@end
