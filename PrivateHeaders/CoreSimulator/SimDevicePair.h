/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSMutableArray, NSUUID, SimDevice, SimDeviceNotificationManager, SimDeviceSet;
@protocol OS_dispatch_queue;

@interface SimDevicePair : NSObject <SimDeviceNotifier>
{
    BOOL _active;
    BOOL _connected;
    NSUUID *_UUID;
    SimDevice *_gizmo;
    SimDevice *_companion;
    SimDeviceSet *_deviceSet;
    NSObject<OS_dispatch_queue> *_pairingStateQueue;
    NSMutableArray *_disconnectSources;
    unsigned long long _gizmoNotificationRegID;
    unsigned long long _companionNotificationRegID;
    NSObject<OS_dispatch_queue> *_stateVariableQueue;
    SimDeviceNotificationManager *_notificationManager;
}

+ (BOOL)testPossiblePairingWithDeviceTypeA:(id)arg1 RuntimeA:(id)arg2 DeviceTypeB:(id)arg3 RuntimeB:(id)arg4 error:(id *)arg5;
+ (id)SimDevicePairWithUUID:(id)arg1 gizmo:(id)arg2 companion:(id)arg3 active:(BOOL)arg4 connected:(BOOL)arg5 deviceSet:(id)arg6;
@property (retain, nonatomic) SimDeviceNotificationManager *notificationManager;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *stateVariableQueue;
@property (nonatomic, assign) unsigned long long companionNotificationRegID;
@property (nonatomic, assign) unsigned long long gizmoNotificationRegID;
@property (retain, nonatomic) NSMutableArray *disconnectSources;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *pairingStateQueue;
@property (nonatomic, weak) SimDeviceSet *deviceSet;
@property (retain, nonatomic) SimDevice *companion;
@property (retain, nonatomic) SimDevice *gizmo;
@property (copy, nonatomic) NSUUID *UUID;

- (void)endPairedDeviceMonitoring;
- (void)ONPSQ_endPairedDeviceMonitoring;
- (void)beginPairedDeviceMonitoring;
- (void)ONPSQ_setActiveOnPairedDevices;
- (void)ONPSQ_disconnectIPCRelayOnDevices;
- (void)ONPSQ_connectIPCRelayOnDevices;
- (void)addDisconnectMonitorPort:(unsigned int)arg1;
- (void)setConnected:(BOOL)arg1;
@property (readonly, nonatomic) BOOL connected;
@property (nonatomic, assign) BOOL active;
- (void)setActiveAsyncWithCompletionQueue:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (BOOL)setActiveWithError:(id *)arg1;
- (void)handleXPCNotificationPairConnectionStateChanged:(NSDictionary *)arg1;
- (void)handleXPCNotificationPairSetActive:(NSDictionary *)arg1;
- (void)handleXPCNotification:(NSDictionary *)arg1;
- (void)handleXPCRequestPairSetActive:(NSDictionary *)arg1;
- (void)handleXPCRequest:(NSDictionary *)arg1;
- (struct NSMutableDictionary *)newDevicePairNotification;
- (struct NSMutableDictionary *)createXPCNotification:(id)arg1;
- (struct NSMutableDictionary *)createXPCRequest:(id)arg1;
- (long long)compare:(id)arg1;
- (id)description;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (void)invalidate;
- (id)initWithUUID:(id)arg1 gizmo:(id)arg2 companion:(id)arg3 active:(BOOL)arg4 connected:(BOOL)arg5 deviceSet:(id)arg6;

@end

