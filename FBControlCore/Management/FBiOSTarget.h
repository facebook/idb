/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

/**
 Common Properties of Devices & Simulators.
 */
@protocol FBiOSTarget <NSObject>

/**
 The Unique Device Identifier of the iOS Target.
 */
@property (nonatomic, copy, readonly, nonnull) NSString *udid;

@end
