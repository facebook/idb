/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

__attribute__((visibility("hidden")))
@interface SimDeviceNotificationManager : NSObject <SimDeviceNotifier>
{
    NSObject<OS_dispatch_queue> *_handlersQueue;
    NSMutableDictionary *_handlers;
    unsigned long long _next_regID;
    NSObject<OS_dispatch_queue> *_sendQueue;
}

@property(retain, nonatomic) NSObject<OS_dispatch_queue> *sendQueue; // @synthesize sendQueue=_sendQueue;
@property(nonatomic) unsigned long long next_regID; // @synthesize next_regID=_next_regID;
@property(retain, nonatomic) NSMutableDictionary *handlers; // @synthesize handlers=_handlers;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *handlersQueue; // @synthesize handlersQueue=_handlersQueue;
- (void)sendNotification:(id)arg1 completionQueue:(id)arg2 completionBlock:(CDUnknownBlockType)arg3;
- (void)sendNotification:(id)arg1;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (id)init;

@end

