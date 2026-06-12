/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 The Error Domain for XCTestBootstrap Errors.
 */
extern NSString *const FBDeviceControlErrorDomain;

/**
 An Error Builder for FBDeviceControl Errors.
 */
@interface FBDeviceControlError : FBControlCoreError

@end
