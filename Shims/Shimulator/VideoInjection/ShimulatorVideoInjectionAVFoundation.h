/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The AVFoundation objects the virtual camera hands to apps. Each is allocated but never
 * initialised by the framework, so `init` installs the private state holder its -dealloc needs.
 */
@interface ShimulatorFrameRateRange : AVFrameRateRange
@property (nonatomic) double rate;
- (instancetype)init;
@end

@interface ShimulatorCaptureDeviceFormat : AVCaptureDeviceFormat
@property (nullable, nonatomic, strong) __attribute__((NSObject)) CMVideoFormatDescriptionRef formatDescriptionRef;
@property (nonatomic, strong) ShimulatorFrameRateRange *range;
- (instancetype)init;
@end

@interface ShimulatorCaptureDevice : AVCaptureDevice
@property (atomic, strong) ShimulatorCaptureDeviceFormat *virtualFormat;
@property (nonatomic) AVCaptureDevicePosition virtualPosition;
@property (nonatomic, copy) NSString *virtualUniqueID;
- (instancetype)init;
@end

@interface ShimulatorCaptureInputPort : AVCaptureInputPort
@property (nullable, nonatomic, weak) AVCaptureInput *owningInput;
@property (nonatomic) BOOL storedEnabled;
- (instancetype)init;
@end

@interface ShimulatorCaptureDeviceInput : AVCaptureDeviceInput
@property (nonatomic, strong) ShimulatorCaptureDevice *virtualDevice;
@property (nonatomic, strong) NSArray<AVCaptureInputPort *> *virtualPorts;
- (instancetype)init;
@end

@interface ShimulatorCaptureConnection : AVCaptureConnection
@property (atomic, strong) NSArray<AVCaptureInputPort *> *virtualPorts;
@property (nullable, nonatomic, weak) AVCaptureOutput *virtualOutput;
@property (nullable, nonatomic, weak) AVCaptureSession *virtualSession;
/** Clockwise, and one of 0, 90, 180 or 270 once set; negative until then. */
@property (nonatomic) CGFloat storedRotationAngle;
/**
 The angle set, or until then the native landscape angle of the camera the connection reads: 0 for a back camera and
 180 (`LandscapeLeft`) for a front one, which is mounted the other way up.
 */
@property (nonatomic, readonly) CGFloat rotationAngle;
/**
 The angle the frames are turned by. A front camera's landscape angles are swapped, so an app gets the same native
 frame from the front camera at `LandscapeLeft` as from the back one at `LandscapeRight`, as on a device.
 */
@property (nonatomic, readonly) CGFloat frameRotationAngle;
@property (nonatomic) BOOL storedEnabled;
@property (nonatomic) BOOL storedMirrored;
/** YES by default: a front camera's preview is then mirrored and its outputs are not, as on a device. */
@property (nonatomic) BOOL storedAutomaticallyAdjustsMirroring;
- (instancetype)init;
@end

@interface ShimulatorCaptureDiscoverySession : AVCaptureDeviceDiscoverySession
@property (nonatomic, strong) NSArray<AVCaptureDevice *> *virtualDevices;
- (instancetype)init;
@end

@interface ShimulatorCaptureResolvedPhotoSettings : AVCaptureResolvedPhotoSettings
@property (nonatomic) int64_t storedUniqueID;
@property (nonatomic) CMVideoDimensions storedPhotoDimensions;
- (instancetype)init;
@end

@interface ShimulatorCapturePhoto : AVCapturePhoto
@property (nullable, nonatomic, strong) NSData *jpeg;
@property (nullable, nonatomic, strong) __attribute__((NSObject)) CVPixelBufferRef storedPixelBuffer;
@property (nullable, nonatomic, strong) __attribute__((NSObject)) CGImageRef storedImage;
@property (nonatomic) CMTime storedTimestamp;
@property (nullable, nonatomic, strong) AVCaptureResolvedPhotoSettings *storedResolvedSettings;
- (instancetype)init;
@end

NS_ASSUME_NONNULL_END
