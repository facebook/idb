/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSDate, NSDictionary, NSMutableArray, NSMutableDictionary, NSString, SimProfilesPathMonitor;
@protocol OS_dispatch_queue, OS_xpc_object;

@interface SimServiceContext : NSObject
{
    NSMutableArray *_supportedDeviceTypes;
    NSMutableDictionary *_supportedDeviceTypesByIdentifier;
    NSMutableDictionary *_supportedDeviceTypesByAlias;
    NSMutableArray *_supportedRuntimes;
    NSMutableDictionary *_supportedRuntimesByIdentifier;
    NSMutableDictionary *_supportedRuntimesByAlias;
    NSString *_developerDir;
    NSMutableDictionary *_allDeviceSets;
    BOOL _valid;
    BOOL _initialized;
    long long _connectionType;
    NSObject<OS_xpc_object> *_serviceConnection;
    NSObject<OS_dispatch_queue> *_serviceConnectionQueue;
    NSDate *_lastConnectionTime;
    SimProfilesPathMonitor *_profileMonitor;
    NSObject<OS_dispatch_queue> *_profileQueue;
    NSObject<OS_dispatch_queue> *_allDeviceSetsQueue;
}

+ (void)setSharedContextConnectionType:(long long)arg1;
+ (id)serviceContextForDeveloperDir:(id)arg1 connectionType:(long long)arg2 error:(id *)arg3;
+ (id)sharedServiceContextForDeveloperDir:(id)arg1 error:(id *)arg2;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *allDeviceSetsQueue;
@property (nonatomic, assign) BOOL initialized;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *profileQueue;
@property (retain, nonatomic) SimProfilesPathMonitor *profileMonitor;
@property (retain, nonatomic) NSDate *lastConnectionTime;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *serviceConnectionQueue;
@property (retain, nonatomic) NSObject<OS_xpc_object> *serviceConnection;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, copy) NSString *developerDir;
@property (nonatomic, assign) long long connectionType;

- (void)handleXPCEvent:(id)arg1;
- (void)handleReconnectionBookkeeping;
- (void)addProfilesForDeveloperDir:(id)arg1;
- (void)supportedRuntimesAddProfilesAtPath:(id)arg1;
- (void)supportedDeviceTypesAddProfilesAtPath:(id)arg1;
- (void)serviceAddProfilesAtPath:(id)arg1;
- (void)addProfilesAtPath:(id)arg1;
@property (nonatomic, copy, readonly) NSDictionary *supportedRuntimesByAlias;
@property (nonatomic, copy, readonly) NSDictionary *supportedRuntimesByIdentifier;
@property (nonatomic, copy, readonly) NSArray *bundledRuntimes;
@property (nonatomic, copy, readonly) NSArray *supportedRuntimes;
@property (nonatomic, copy, readonly) NSDictionary *supportedDeviceTypesByAlias;
@property (nonatomic, copy, readonly) NSDictionary *supportedDeviceTypesByIdentifier;
@property (nonatomic, copy, readonly) NSArray *bundledDeviceTypes;
@property (nonatomic, copy, readonly) NSArray *supportedDeviceTypes;
- (id)allDeviceSets;
- (id)deviceSetWithPath:(id)arg1 error:(id *)arg2;
- (id)defaultDeviceSetWithError:(id *)arg1;
- (void)dealloc;
- (void)connect;
- (id)initWithDeveloperDir:(id)arg1 connectionType:(long long)arg2;

@end

