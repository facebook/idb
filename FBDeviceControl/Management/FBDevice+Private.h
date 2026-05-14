/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBDevice.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDevice;
@class FBAMRestorableDevice;
@class FBDeviceVideoRecordingCommands;
@class FBDeviceXCTestCommands;
@class FBiOSTargetCommandForwarder;

@interface FBDevice ()

@property (nullable, nonatomic, readwrite, strong) FBAMDevice *amDevice;
@property (nullable, nonatomic, readwrite, strong) FBAMRestorableDevice *restorableDevice;
@property (nonatomic, readonly, strong) FBiOSTargetCommandForwarder *forwarder;

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(nullable FBAMDevice *)amDevice restorableDevice:(nullable FBAMRestorableDevice *)restorableDevice logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
