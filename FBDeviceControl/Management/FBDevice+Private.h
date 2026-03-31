/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBDevice.h>

@class FBAMDevice;
@class FBAMRestorableDevice;
@class FBDeviceVideoRecordingCommands;
@class FBDeviceXCTestCommands;
@class FBiOSTargetCommandForwarder;

@interface FBDevice ()

@property (nullable, nonatomic, readwrite, strong) FBAMDevice *amDevice;
@property (nullable, nonatomic, readwrite, strong) FBAMRestorableDevice *restorableDevice;
@property (nonnull, nonatomic, readonly, strong) FBiOSTargetCommandForwarder *forwarder;

- (nonnull instancetype)initWithSet:(nonnull FBDeviceSet *)set amDevice:(nullable FBAMDevice *)amDevice restorableDevice:(nullable FBAMRestorableDevice *)restorableDevice logger:(nonnull id<FBControlCoreLogger>)logger;

@end
