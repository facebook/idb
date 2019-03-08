/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class DTXConnection, NSString, DTXMessage;
@protocol DTXAllowedRPC;

@interface DTXChannel : NSObject// <DTXMessenger>
{
    DTXConnection *_connection;
    NSObject<OS_dispatch_queue> *_serialQueue;
    NSObject<OS_dispatch_queue> *_atomicHandlers;
    id <DTXAllowedRPC> _dispatchTarget;
    CDUnknownBlockType _messageHandler;
    CDUnknownBlockType _dispatchValidator;
    BOOL _canceled;
    unsigned int _channelCode;
    int _compressionTypeHint;
}

@property(nonatomic) int compressionTypeHint; // @synthesize compressionTypeHint=_compressionTypeHint;
@property(readonly, retain, nonatomic) DTXConnection *connection; // @synthesize connection=_connection;
@property(readonly, nonatomic) unsigned int channelCode; // @synthesize channelCode=_channelCode;
@property BOOL isCanceled; // @synthesize isCanceled=_canceled;
- (void)sendMessageSync:(DTXMessage *)message replyHandler:(void (^)(DTXMessage *responseMessage))replyHandler;
- (void)sendMessage:(DTXMessage *)message replyHandler:(void (^)(DTXMessage *responseMessage))replyHandler;
- (BOOL)sendMessageAsync:(DTXMessage *)message replyHandler:(void (^)(DTXMessage *responseMessage))replyHandler;
- (void)sendControlSync:(DTXMessage *)message replyHandler:(void (^)(DTXMessage *responseMessage))replyHandler;
- (void)sendControlAsync:(DTXMessage *)message replyHandler:(void (^)(DTXMessage *responseMessage))replyHandler;
- (void)_setTargetQueue:(id)arg1;
- (void)resume;
- (void)suspend;
- (void)cancel;
- (void)registerDisconnectHandler:(CDUnknownBlockType)arg1;
- (void)_setDispatchValidator:(CDUnknownBlockType)arg1;
@property(retain) id <DTXAllowedRPC> dispatchTarget;
@property(copy) CDUnknownBlockType messageHandler;
- (void)_scheduleMessage:(id)arg1 tracker:(id)arg2 withHandler:(CDUnknownBlockType)arg3;
- (void)_scheduleBlock:(CDUnknownBlockType)arg1;
- (void)dealloc;
- (id)initWithConnection:(id)arg1 channelIdentifier:(unsigned int)arg2;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

