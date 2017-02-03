/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSArray, NSDictionary, NSMutableDictionary, NSString, SimDeviceNotificationManager, SimServiceContext;
@protocol OS_dispatch_queue;

@interface SimDeviceSet : NSObject <SimDeviceNotifier>
{
    NSString *_setPath;
    NSObject<OS_dispatch_queue> *_devicesQueue;
    NSMutableDictionary *__devicesByUDID;
    NSMutableDictionary *_devicesNotificationRegIDs;
    NSMutableDictionary *__devicePairsByUUID;
    NSMutableDictionary *_devicePairsNotificationRegIDs;
    SimServiceContext *_serviceContext;
    SimDeviceNotificationManager *_notificationManager;
    NSObject<OS_dispatch_queue> *_defaultCreatedDevicesQueue;
    NSMutableDictionary *_defaultCreatedDevices;
    NSString *_defaultCreatedLastDeveloperDir;
}

+ (id)defaultSetPath;
@property (nonatomic, copy) NSString *defaultCreatedLastDeveloperDir;
@property (retain, nonatomic) NSMutableDictionary *defaultCreatedDevices;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *defaultCreatedDevicesQueue;
@property (retain, nonatomic) SimDeviceNotificationManager *notificationManager;
@property (retain, nonatomic) SimServiceContext *serviceContext;
@property (retain, nonatomic) NSMutableDictionary *devicePairsNotificationRegIDs;
@property (retain, nonatomic) NSMutableDictionary *_devicePairsByUUID;
@property (retain, nonatomic) NSMutableDictionary *devicesNotificationRegIDs;
@property (retain, nonatomic) NSMutableDictionary *_devicesByUDID;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *devicesQueue;
@property (copy, nonatomic) NSString *setPath;

- (void)handleXPCRequestUnpair:(NSDictionary *)arg1;
- (void)handleXPCRequestPair:(NSDictionary *)arg1;
- (void)handleXPCRequestDeleteDevice:(NSDictionary *)arg1 device:(id)arg2;
- (void)handleXPCRequestCloneDevice:(NSDictionary *)arg1 device:(id)arg2;
- (void)handleXPCRequestCreateDevice:(NSDictionary *)arg1;
- (void)handleXPCRequest:(NSDictionary *)arg1;
- (void)handleXPCNotificationDevicePairRemoved:(NSDictionary *)arg1;
- (void)handleXPCNotificationDevicePairAdded:(NSDictionary *)arg1;
- (void)handleXPCNotificationDeviceRemoved:(NSDictionary *)arg1;
- (void)handleXPCNotificationDeviceAdded:(NSDictionary *)arg1;
- (void)handleXPCNotification:(NSDictionary *)arg1;
- (BOOL)unpairDevicePair:(id)arg1 error:(id *)arg2;
- (void)unpairDevicePairAsync:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)unpairDevicePairAsync:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (id)createDevicePairWithGizmo:(id)arg1 companion:(id)arg2 error:(id *)arg3;
- (void)createDevicePairAsyncWithGizmo:(id)arg1 companion:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)createDevicePairAsyncWithGizmo:(id)arg1 companion:(id)arg2 completionQueue:(id)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (BOOL)testDevicePairingBetweenGizmo:(id)arg1 companion:(id)arg2 error:(id *)arg3;
- (BOOL)deleteDevice:(id)arg1 error:(id *)arg2;
- (void)deleteDeviceAsync:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (id)cloneDevice:(id)arg1 name:(id)arg2 error:(id *)arg3;
- (void)cloneDeviceAsync:(id)arg1 name:(id)arg2 completionQueue:(id)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (void)deleteDeviceAsync:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (id)createDeviceWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 error:(id *)arg4;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 completionQueue:(id)arg4 completionHandler:(CDUnknownBlockType)arg5;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (void)sendNotification:(id)arg1;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (unsigned long long)registerNotificationHandler:(CDUnknownBlockType)arg1;
- (void)removeDevicePairAsync:(id)arg1;
- (void)_onDevicesQueue_addDevicePair:(id)arg1;
- (void)addDevicePair:(id)arg1;
- (void)addDevicePairAsync:(id)arg1;
- (void)removeDeviceAsync:(id)arg1;
- (void)_onDeviceQueue_addDevice:(id)arg1;
- (void)addDevice:(id)arg1;
- (void)addDeviceAsync:(id)arg1;
- (void)_onDefaultCreatedDevicesQueue_updateDefaultDevicePairingsForDeveloperDir:(id)arg1;
- (void)_onDefaultCreatedDevicesQueue_updateDefaultDevicesForDeveloperDir:(id)arg1;
- (void)updateDefaultDevicesAndPairingsForDeveloperDir:(id)arg1;
- (id)devicePairsContainingDevice:(id)arg1;
- (id)devicePairsContainingDeviceUDID:(id)arg1;
@property (nonatomic, copy, readonly) NSArray *availableDevicePairs;
@property (nonatomic, copy, readonly) NSArray *devicePairs;
@property (nonatomic, copy, readonly) NSDictionary *devicePairsByUUID;
@property (nonatomic, copy, readonly) NSArray *availableDevices;
@property (nonatomic, copy, readonly) NSArray *devices;
- (BOOL)isDeviceInSet:(id)arg1;
@property (nonatomic, copy, readonly) NSDictionary *devicesByUDID;
- (id)description;
- (void)saveToDisk;
- (void)processDeviceSetPlist;
- (id)initWithSetPath:(id)arg1 serviceContext:(id)arg2;
- (BOOL)subscribeToNotificationsWithError:(id *)arg1;

@end

