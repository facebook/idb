/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SimScreenProperties <FoundationXPCProtocolProxyable>
@property (nonatomic, readonly, nullable) id uniqueId;
@end

NS_ASSUME_NONNULL_END
