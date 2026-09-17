/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Raw values mirror CoreSimulator's -[SimDeviceType productFamilyID] and must not be renumbered.
 */
typedef NS_ENUM(NSUInteger, FBControlCoreProductFamily) {
  FBControlCoreProductFamilyUnknown = 0,
  FBControlCoreProductFamilyiPhone = 1,
  FBControlCoreProductFamilyiPad = 2,
  FBControlCoreProductFamilyAppleTV = 3,
  FBControlCoreProductFamilyAppleWatch = 4,
  FBControlCoreProductFamilyMac = 5,
};

#import <FBControlCore/FBControlCore-SwiftImport.h>
