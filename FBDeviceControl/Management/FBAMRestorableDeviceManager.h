/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBDeviceControl/FBDeviceManager.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMRestorableDevice;

/**
 Class for obtaining FBAMRestorableDevice instances.
 */
@interface FBAMRestorableDeviceManager : FBDeviceManager<FBAMRestorableDevice *>

/**
 The Designated Initializer

 @param calls the AMDCalls to use.
 @param queue the queue to serialize on.
 @param ecidFilter an ECID filter to apply.
 @param logger the logger to use.
 @return a new FBAMRestorableDeviceManager instance
 */
- (instancetype)initWithCalls:(AMDCalls)calls queue:(dispatch_queue_t)queue ecidFilter:(nullable NSString *)ecidFilter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
