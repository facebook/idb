/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

@class DVTiOSDevice;
@class FBDeviceSet;
@class FBProductBundle;
@class FBTestRunnerConfiguration;
@protocol FBDeviceOperator;
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

/**
 Class that wraps DVTAbstractiOSDevice and it's device operator that can perform actions on it.
 */
@interface FBDevice : NSObject <FBiOSTarget>

/**
 The Device Set to which the Device Belongs.
 */
@property (nonatomic, weak, readonly) FBDeviceSet *set;

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
 Add a forwarding class. The class has to conform to the FBiOSTargetCommand
 protocol. The class is added globally for all all devices and needs to
 be added before FBDevice instances are created.

 @param class Command class to be added.
 @returns if it succeeded
 */
+ (BOOL)addForwardingCommandClass:(Class)class error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
