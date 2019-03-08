/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class DTXChannel, Protocol;

@interface DTXProxyChannel : NSObject
{
    Protocol *_remoteInterface;
    Protocol *_exportedInterface;
    DTXChannel *_channel;
}

@property(retain, nonatomic) DTXChannel *channel; // @synthesize channel=_channel;
@property Protocol *remoteInterface; // @synthesize remoteInterface=_remoteInterface;
- (void)_sendInvocationMessage:(id)arg1;
- (void)setExportedObject:(id)arg1 queue:(id)arg2;
- (void)_validateDispatch:(id)arg1;
- (void)cancel;
@property(readonly) id remoteObjectProxy;
- (id)initWithChannel:(id)arg1 remoteProtocol:(id)arg2 localProtocol:(id)arg3;
- (void)dealloc;

@end

