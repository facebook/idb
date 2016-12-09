/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Running Tests on a device.
 */
@interface FBDeviceTestRunStrategy : NSObject

+ (instancetype)strategyWithDevice:(FBDevice *)device
                      testHostPath:(nullable NSString *)testHostPath
                    testBundlePath:(nullable NSString *)testBundlePath
                       withTimeout:(NSTimeInterval)timeout
                     withArguments:(NSArray<NSString *> *)arguments;

- (BOOL)startWithError:(NSError **)error;

- (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)buildXCTestRunProperties;

@end

NS_ASSUME_NONNULL_END
