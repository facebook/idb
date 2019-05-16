/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBDevice.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDevice;
@class FBDLDevice;
@class FBDeviceVideoRecordingCommands;
@class FBDeviceXCTestCommands;
@class FBiOSTargetCommandForwarder;

@interface FBDevice ()

@property (nonatomic, strong, readonly) FBiOSTargetCommandForwarder *forwarder;
@property (nonatomic, strong, readonly) FBAMDevice *amDevice;
@property (nonatomic, strong, readonly) FBDLDevice *dlDevice;

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)device logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
