/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBSimulatorIndigoHID.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Constructs GSEvent payloads for PurpleWorkspacePort.
 Mirrors FBSimulatorIndigoHID (which constructs Indigo payloads for IndigoHIDRegistrationPort).

 The returned NSData contains a complete mach message (including mach_msg_header_t)
 ready to be sent via mach_msg_send. The msgh_remote_port field is left as 0
 and must be patched by the transport (FBSimulatorHID.sendPurpleEvent:) before sending.

 See GSEvent.h for the wire format documentation.
 */
@interface FBSimulatorPurpleHID : NSObject

/**
 Creates a new FBSimulatorPurpleHID instance.
 Unlike FBSimulatorIndigoHID, this class has no dlsym dependencies —
 payloads are constructed from documented constants.

 @return a new FBSimulatorPurpleHID instance.
 */
+ (instancetype)purple;

/**
 Constructs a GSEvent orientation change mach message.
 The message uses GSEvent type 50 (kGSEventDeviceOrientationChanged) with the host flag.

 @param orientation the desired device orientation.
 @return an NSData containing the complete mach message (112 bytes, msgh_size=108).
 */
- (NSData *)orientationEvent:(FBSimulatorHIDDeviceOrientation)orientation;

@end

NS_ASSUME_NONNULL_END
