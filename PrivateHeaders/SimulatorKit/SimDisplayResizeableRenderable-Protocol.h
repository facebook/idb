/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@protocol SimDisplayResizeableRenderable <FoundationXPCProtocolProxyable>
- (void)didChangeOptimizedDisplaySize:(struct CGSize)arg1;
- (void)didChangeDisplaySize:(struct CGSize)arg1;
@end
