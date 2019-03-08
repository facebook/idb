/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>
#import <Foundation/Foundation.h>

@protocol SimDisplayRenderable <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) long long displaySizeInBytes;
@property (nonatomic, readonly) long long displayPitch;
@property (nonatomic, readonly) struct CGSize optimizedDisplaySize;
@property (nonatomic, readonly) struct CGSize displaySize;

// Added in Xcode 9 as -[SimDeviceIOClient attachConsumer:] methods have been removed.
- (void)unregisterDamageRectanglesCallbackWithUUID:(NSUUID *)arg1;
- (void)registerCallbackWithUUID:(NSUUID *)arg1 damageRectanglesCallback:(void (^)(NSArray *))arg2;

@end
