/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceBootInfo.h>

@interface SimDeviceBootInfo (Removed)

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). SimDeviceBootInfo no longer
 implements NSCoding directly; serialization moved to the ROCK session API
 (-rockEncodeWithSessionManager:error: / +rockDecodeWithXPCObject:sessionManager:error:).
 +supportsSecureCoding remains. Not called by idb/FBSimulatorControl.
 */
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;

@end
