/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimPasteboard-Protocol.h>

@class NSArray, NSDate, SimDevice, SimDeviceNotificationManager, SimDevicePasteboardConnection, SimMachPortServer;
@protocol OS_dispatch_queue, OS_dispatch_source;

@interface SimDevicePasteboard : NSObject <SimPasteboard>
{
    NSObject<OS_dispatch_queue> *_itemsQueue;
    unsigned long long _changeCount;
    NSArray *_items;
    SimDevice *_device;
    SimDevicePasteboardConnection *_pasteboardConnection;
    SimMachPortServer *_notificationServer;
    SimDeviceNotificationManager *_notificationManager;
    unsigned long long _bootMonitorRegistrationID;
    SimMachPortServer *_promisedDataServer;
    NSObject<OS_dispatch_queue> *_subscriptionStateQueue;
    NSDate *_lastConnectionTime;
    NSObject<OS_dispatch_source> *_lifecycleSource;
    NSArray *_stagedItems;
}

@property (atomic, copy) NSArray *stagedItems;
@property (retain, nonatomic) NSObject<OS_dispatch_source> *lifecycleSource;
@property (retain, nonatomic) NSDate *lastConnectionTime;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *subscriptionStateQueue;
@property (retain, nonatomic) SimMachPortServer *promisedDataServer;
@property (nonatomic, assign) unsigned long long bootMonitorRegistrationID;
@property (retain, nonatomic) SimDeviceNotificationManager *notificationManager;
@property (retain, nonatomic) SimMachPortServer *notificationServer;
@property (retain, nonatomic) SimDevicePasteboardConnection *pasteboardConnection;
@property (nonatomic, weak) SimDevice *device;
@property (atomic, copy) NSArray *items;
@property (atomic, assign) unsigned long long changeCount; // @synthesize changeCount=_changeCount;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *itemsQueue;

- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (void)syncBarrier;
- (unsigned long long)setPasteboardWithItems:(id)arg1 error:(id *)arg2;
- (void)setPasteboardAsyncWithItems:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (id)itemsFromPasteboardWithTypes:(id)arg1 error:(id *)arg2;
- (void)itemsFromPasteboardAsyncWithTypes:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (id)generateSimPasteboardItemsWithTypes:(id)arg1 changeCount:(unsigned long long)arg2;
- (void)setItems:(id)arg1 changeCount:(unsigned long long)arg2;
- (void)pasteboardHasChanged:(unsigned long long)arg1 itemsTypes:(id)arg2;
- (void)_onSubscriptionStateQueue_unsubscribe;
- (void)addDisconnectMonitorPort:(unsigned int)arg1;
- (void)startMonitorLifecyclePort;
- (void)_onSubscriptionStateQueue_subscribe;
- (id)description;
- (void)dealloc;
- (id)initWithDevice:(id)arg1;

@end
