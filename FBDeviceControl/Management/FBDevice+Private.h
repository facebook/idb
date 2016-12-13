/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBDevice.h>

NS_ASSUME_NONNULL_BEGIN

@class DVTiOSDevice;
@class FBAMDevice;
@class FBDeviceVideoRecordingCommands;
@protocol FBDeviceOperator;

@interface FBDevice ()

@property (nonatomic, strong, readonly) FBAMDevice *amDevice;
@property (nonatomic, strong, readonly) FBDeviceVideoRecordingCommands *recordingCommand;

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)device logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
