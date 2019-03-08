/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@protocol SimDisplayDamageRectangleDelegate <FoundationXPCProtocolProxyable>
- (void)didReceiveDamageRect:(struct CGRect)arg1;
@end
