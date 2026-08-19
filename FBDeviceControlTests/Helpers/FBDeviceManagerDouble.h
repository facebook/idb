/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBDeviceControl/FBDeviceManager.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A concrete FBDeviceManager for tests. Swift cannot subclass an Objective-C
 class with lightweight generics, so the double lives here.

 constructPublic returns a plain NSObject stand-in and extractPrivateReference
 always returns NULL, so every deviceConnected: call takes the
 "appeared for the first time" path.
 */
@interface FBDeviceManagerDouble : FBDeviceManager <NSObject *>

@end

NS_ASSUME_NONNULL_END
