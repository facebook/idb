/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBTestManagerProcessInteractionDelegate.h>

@protocol FBDeviceOperator;
@protocol FBiOSTarget;

/**
 Makes a FBTestManagerProcessInteractionDelegate from a Device Operator.
 */
@interface FBTestManagerProcessInteractionOperator : NSObject <FBTestManagerProcessInteractionDelegate>

/**
 Constructs a FBTestManagerProcessInteractionOperator

 @param iosTarget the iOS Target.
 @return a new FBTestManagerProcessInteractionOperator instance.
 */
+ (instancetype)withIOSTarget:(id<FBiOSTarget>)iosTarget;

/**
 The Device Operator.
 */
@property (nonatomic, strong, readonly) id<FBiOSTarget> iosTarget;

@end
