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

/**
 Makes a FBTestManagerProcessInteractionDelegate from a Device Operator.
 */
@interface FBTestManagerProcessInteractionOperator : NSObject <FBTestManagerProcessInteractionDelegate>

/**
 Constructs a FBTestManagerProcessInteractionOperator

 @param deviceOperator the device operator.
 @return a new FBTestManagerProcessInteractionOperator instance.
 */
+ (instancetype)withDeviceOperator:(id<FBDeviceOperator>)deviceOperator;

/**
 The Device Operator.
 */
@property (nonatomic, strong, readonly) id<FBDeviceOperator> deviceOperator;

@end
