/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 The Error Domain for FBSimulatorControl.
 */
extern NSString * _Nonnull const FBSimulatorControlErrorDomain;

// FBSimulatorError class is now implemented in Swift.
#import <FBSimulatorControl/FBSimulatorBootConfiguration.h>
#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
