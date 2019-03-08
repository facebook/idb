/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceBootInfo.h>

@interface SimDeviceBootInfo (SimulatorKit)
@property (nonatomic, readonly) BOOL isSuccess;
@property (nonatomic, readonly) BOOL isWaitable;
@end
