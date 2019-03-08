/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimPasteboard-Protocol.h>

@class NSArray, NSPasteboard, SimDeviceNotificationManager;
@protocol OS_dispatch_queue, OS_dispatch_source;

@interface SimNSPasteboard : NSObject <SimPasteboard>
{
    unsigned long long _refreshResolveCount;
    NSObject<OS_dispatch_queue> *_nsPasteboardQueue;
    NSObject<OS_dispatch_source> *_pollPastboardChangeTimer;
    NSObject<OS_dispatch_queue> *_pollPastboardChangeTimerQueue;
    NSArray *_items;
    unsigned long long _changeCount;
    NSPasteboard *_nsPasteboard;
    SimDeviceNotificationManager *_notificationManager;
}

+ (id)pasteboardForNSPasteboard:(id)arg1 refreshResolveCount:(unsigned long long)arg2;
@property (retain, nonatomic) SimDeviceNotificationManager *notificationManager;
@property (retain, nonatomic) NSPasteboard *nsPasteboard;
@property (atomic, assign) unsigned long long changeCount; // @synthesize changeCount=_changeCount;
@property (atomic, copy) NSArray *items;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *pollPastboardChangeTimerQueue;
@property (retain, nonatomic) NSObject<OS_dispatch_source> *pollPastboardChangeTimer;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *nsPasteboardQueue;
@property (atomic, assign) unsigned long long refreshResolveCount; // @synthesize refreshResolveCount=_refreshResolveCount;

- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (unsigned long long)setPasteboardWithItems:(id)arg1 error:(id *)arg2;
- (void)setPasteboardAsyncWithItems:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)syncBarrier;
- (void)sendPasteboardChangedNotification;
- (void)refreshItemsFromNSPasteboard;
- (id)description;
- (void)dealloc;
- (id)initWithNSPasteboard:(id)arg1 refreshResolveCount:(unsigned long long)arg2;

@end
