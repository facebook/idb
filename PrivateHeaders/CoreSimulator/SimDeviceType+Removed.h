/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceType.h>

@interface SimDeviceType (Removed)

/**
 Removed in Xcode 8.1.
 */
+ (NSArray<SimDeviceType *> *)supportedDeviceTypes;

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). The bundle/path initializers are no
 longer exposed; SimDeviceType instances are vended via SimServiceContext. Not
 called by idb/FBSimulatorControl.
 */
- (id)initWithBundle:(id)arg1;
- (id)initWithPath:(id)arg1;

@end
