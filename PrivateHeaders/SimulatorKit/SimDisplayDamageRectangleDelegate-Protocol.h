/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

/**
 As of Xcode 27 (CoreSimulator 1155.4) this protocol is vended by CoreSimDeviceIO
 (re-exported by CoreSimulator), not SimulatorKit, which is now almost entirely
 Swift. Declaration retained here; resolved at runtime via the re-export. Eventual
 home: a CoreSimDeviceIO header group.
 */
@protocol SimDisplayDamageRectangleDelegate <FoundationXPCProtocolProxyable>
- (void)didReceiveDamageRect:(struct CGRect)arg1;
@end
