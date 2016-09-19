/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorControlConfiguration;
@class SimServiceContext;

NS_ASSUME_NONNULL_BEGIN

/**
 An FBSimulatorControl wrapper for SimServiceContext.
 */
@interface FBSimulatorServiceContext : NSObject

/**
 Creates a Service Context.

 @param serviceContext the Service Context to wrap.
 @return a Service Context.
 */
+ (instancetype)contextWithServiceContext:(SimServiceContext *)serviceContext;

/**
 The underlying SimServiceContext.
 */
@property (nonatomic, strong, readonly) SimServiceContext *serviceContext;

/**
 Return the paths to all of the device sets.
 */
- (NSArray<NSString *> *)pathsOfAllDeviceSets;

@end

NS_ASSUME_NONNULL_END
