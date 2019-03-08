/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSArray, NSDictionary, NSMutableDictionary, NSString, SimDeviceNotificationManager, SimServiceContext, SimRuntime, SimDeviceType, SimDeviceType, SimDevice;
@protocol OS_dispatch_queue;

@interface SimDeviceSet : NSObject <SimDeviceNotifier>
{
  NSString *_setPath;
  NSObject<OS_dispatch_queue> *_deviceNotificationQueue;
  NSObject<OS_dispatch_queue> *_devicesQueue;
  NSMutableDictionary *__devicesByUDID;
  NSMutableDictionary *_devicesNotificationRegIDs;
  NSMutableDictionary *__devicePairsByUUID;
  NSMutableDictionary *_devicePairsNotificationRegIDs;
  NSMutableDictionary *_deviceDeletionCountByUDID;
  SimServiceContext *_serviceContext;
  SimDeviceNotificationManager *_notificationManager;
  NSObject<OS_dispatch_queue> *_defaultCreatedDevicesQueue;
  NSObject<OS_dispatch_queue> *_deviceDeletionQueue;
  NSObject<OS_dispatch_queue> *_hostDeathQueue;
  NSMutableDictionary *_hostDeathSourceByUDID;
  NSMutableDictionary *_defaultCreatedDevices;
  NSString *_defaultCreatedLastDeveloperDir;
}

+ (id)defaultSetPath;
@property(retain, nonatomic) NSString *defaultCreatedLastDeveloperDir; // @synthesize defaultCreatedLastDeveloperDir=_defaultCreatedLastDeveloperDir;
@property(retain, nonatomic) NSMutableDictionary *defaultCreatedDevices; // @synthesize defaultCreatedDevices=_defaultCreatedDevices;
@property(retain, nonatomic) NSMutableDictionary *hostDeathSourceByUDID; // @synthesize hostDeathSourceByUDID=_hostDeathSourceByUDID;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *hostDeathQueue; // @synthesize hostDeathQueue=_hostDeathQueue;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *deviceDeletionQueue; // @synthesize deviceDeletionQueue=_deviceDeletionQueue;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *defaultCreatedDevicesQueue; // @synthesize defaultCreatedDevicesQueue=_defaultCreatedDevicesQueue;
@property(retain, nonatomic) SimDeviceNotificationManager *notificationManager; // @synthesize notificationManager=_notificationManager;
@property(retain, nonatomic) SimServiceContext *serviceContext; // @synthesize serviceContext=_serviceContext;
@property(retain, nonatomic) NSMutableDictionary *deviceDeletionCountByUDID; // @synthesize deviceDeletionCountByUDID=_deviceDeletionCountByUDID;
@property(retain, nonatomic) NSMutableDictionary *devicePairsNotificationRegIDs; // @synthesize devicePairsNotificationRegIDs=_devicePairsNotificationRegIDs;
@property(retain, nonatomic) NSMutableDictionary *_devicePairsByUUID; // @synthesize _devicePairsByUUID=__devicePairsByUUID;
@property(retain, nonatomic) NSMutableDictionary *devicesNotificationRegIDs; // @synthesize devicesNotificationRegIDs=_devicesNotificationRegIDs;
@property(retain, nonatomic) NSMutableDictionary *_devicesByUDID; // @synthesize _devicesByUDID=__devicesByUDID;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *devicesQueue; // @synthesize devicesQueue=_devicesQueue;
@property(retain, nonatomic) NSObject<OS_dispatch_queue> *deviceNotificationQueue; // @synthesize deviceNotificationQueue=_deviceNotificationQueue;
@property(copy, nonatomic) NSString *setPath; // @synthesize setPath=_setPath;
- (void)handleXPCRequestUnpair:(id)arg1;
- (void)handleXPCRequestPair:(id)arg1;
- (void)handleXPCRequestDeleteDevice:(id)arg1 device:(id)arg2;
- (void)handleXPCRequestCloneDevice:(id)arg1 device:(id)arg2;
- (void)handleXPCRequestCreateDevice:(id)arg1;
- (void)handleXPCRequest:(id)arg1;
- (void)handleXPCNotificationDevicePairRemoved:(id)arg1;
- (void)handleXPCNotificationDevicePairAdded:(id)arg1;
- (void)handleXPCNotificationDeviceRemoved:(id)arg1;
- (void)handleXPCNotificationDeviceAdded:(id)arg1;
- (void)handleXPCNotification:(id)arg1;
- (BOOL)setupHostDeathWatchForDevice:(id)arg1 deathPort:(id)arg2 error:(id *)arg3;
- (void)runBackgroundDeviceDeleteAsync;
- (BOOL)unpairDevicePair:(id)arg1 error:(id *)arg2;
- (void)unpairDevicePairAsync:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)unpairDevicePairAsync:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (id)createDevicePairWithGizmo:(id)arg1 companion:(id)arg2 error:(id *)arg3;
- (void)createDevicePairAsyncWithGizmo:(id)arg1 companion:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)createDevicePairAsyncWithGizmo:(id)arg1 companion:(id)arg2 completionQueue:(id)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (BOOL)testDevicePairingBetweenGizmo:(id)arg1 companion:(id)arg2 error:(id *)arg3;
- (void)shutdownBootedDevicesMatchingVolumeURL:(id)arg1 completionGroup:(id)arg2 deviceShutdownHandler:(CDUnknownBlockType)arg3;
- (id)cloneDevice:(id)arg1 name:(id)arg2 options:(id)arg3 toSet:(id)arg4 error:(id *)arg5;
- (id)cloneDevice:(id)arg1 name:(id)arg2 toSet:(id)arg3 error:(id *)arg4;
- (id)cloneDevice:(id)arg1 name:(id)arg2 options:(id)arg3 error:(id *)arg4;
- (id)cloneDevice:(id)arg1 name:(id)arg2 error:(id *)arg3;
- (void)cloneDeviceAsync:(id)arg1 name:(id)arg2 options:(id)arg3 toSet:(SimDeviceSet *)arg4 completionQueue:(dispatch_queue_t)arg5 completionHandler:(void (^)(NSError *, SimDevice *))arg6;
- (void)cloneDeviceAsync:(id)arg1 name:(id)arg2 toSet:(SimDeviceSet *)arg3 completionQueue:(dispatch_queue_t)arg4 completionHandler:(void (^)(NSError *, SimDevice *))arg5;
- (void)cloneDeviceAsync:(id)arg1 name:(id)arg2 completionQueue:(dispatch_queue_t)arg3 completionHandler:(void (^)(NSError *, SimDevice *))arg4;
- (BOOL)deleteDevice:(id)arg1 error:(id *)arg2;
- (void)deleteDeviceAsync:(id)arg1 completionHandler:(void(^)(NSError *))arg2;
- (void)deleteDeviceAsync:(id)arg1 completionQueue:(dispatch_queue_t)arg2 completionHandler:(void(^)(NSError *))arg3;
- (id)createDeviceWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 options:(id)arg4 error:(id *)arg5;
- (id)createDeviceWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 error:(id *)arg4;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 options:(id)arg4 completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *, SimDevice *))completionHandler;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *, SimDevice *))completionHandler;
- (void)createDeviceAsyncWithType:(id)arg1 runtime:(id)arg2 name:(id)arg3 completionHandler:(void (^)(NSError *, SimDevice *))completionHandler;
- (id)_awaitDevicePairWithUUID:(id)arg1;
- (id)_awaitDeviceWithUDID:(id)arg1;
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
- (void)updateDefaultDevicesAndPairingsForDeveloperDir:(id)arg1 force:(BOOL)arg2;
- (id)devicePairsContainingDevice:(id)arg1;
- (id)devicePairsContainingDeviceUDID:(id)arg1;
@property(readonly, nonatomic) NSArray *availableDevicePairs;
@property(readonly, nonatomic) NSArray *devicePairs;
@property(readonly, nonatomic) NSDictionary *devicePairsByUUID;
@property(readonly, nonatomic) NSArray *availableDevices;
@property(readonly, nonatomic) NSArray *devices;
- (BOOL)isDeviceInSet:(id)arg1;
@property(readonly, nonatomic) NSDictionary *devicesByUDID;
- (id)description;
- (void)saveToDisk;
- (BOOL)processDeviceSetPlist;
- (id)initWithSetPath:(id)arg1 serviceContext:(id)arg2;
- (BOOL)subscribeToNotificationsWithError:(id *)arg1;
- (BOOL)isDefaultSet;

@end
