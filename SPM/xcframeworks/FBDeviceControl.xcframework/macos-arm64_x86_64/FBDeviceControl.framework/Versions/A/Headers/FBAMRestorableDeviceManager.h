/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param ecidFilter an ECID filter to apply.
 @param logger the logger to use.
 @return a new FBAMRestorableDeviceManager instance
 */
- (instancetype)initWithCalls:(AMDCalls)calls workQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue ecidFilter:(NSString *)ecidFilter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
