/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProductBundle;
@class FBTestRunnerConfiguration;

@protocol FBDeviceOperator;

/**
 Class that wraps DVTAbstractiOSDevice and it's device operator that can perform actions on it.
 */
@interface FBDevice : NSObject

/**
 Device operator used to control device
 */
@property (nonatomic, strong, readonly) id<FBDeviceOperator> deviceOperator;

/**
 Device's name
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 Device's model name
 */
@property (nonatomic, copy, readonly) NSString *modelName;

/**
 Device's system Version
 */
@property (nonatomic, copy, readonly) NSString *systemVersion;

/**
 Unique Device IDentifier
 */
@property (nonatomic, copy, readonly) NSString *UDID;

/**
 Architectures suported by device
 */
@property (nonatomic, copy, readonly) NSSet *supportedArchitectures;

/**
 Convenience constructor

 @param deviceOperator device operator used to operate device
 @return instance of FBDevice.
 */
+ (instancetype)deviceWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator;

@end
