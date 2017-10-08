/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
