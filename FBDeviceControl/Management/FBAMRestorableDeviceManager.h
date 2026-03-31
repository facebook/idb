/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBDeviceManager.h>

@class FBAMRestorableDevice;

/**
 Class for obtaining FBAMRestorableDevice instances.
 */
@interface FBAMRestorableDeviceManager : FBDeviceManager <FBAMRestorableDevice *>

/**
 The Designated Initializer

 @param calls the AMDCalls to use.
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param ecidFilter an ECID filter to apply.
 @param logger the logger to use.
 @return a new FBAMRestorableDeviceManager instance
 */
- (nonnull instancetype)initWithCalls:(AMDCalls)calls workQueue:(nonnull dispatch_queue_t)workQueue asyncQueue:(nonnull dispatch_queue_t)asyncQueue ecidFilter:(nonnull NSString *)ecidFilter logger:(nonnull id<FBControlCoreLogger>)logger;

@end
