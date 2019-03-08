/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceSet.h>

@interface SimDeviceSet (Removed)

/**
 Removed in Xcode 8.1.
 */
+ (instancetype)defaultSet;
+ (instancetype)setForSetPath:(NSString *)setPath;

@end
