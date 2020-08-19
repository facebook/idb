/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceNotifier-Protocol.h>
#import <CoreSimulator/CoreSimulator+BlockDefines.h>

@class NSArray, NSDate, NSDictionary, NSMachPort, NSMutableArray, NSMutableDictionary, NSString, NSUUID, SimDeviceBootInfo, SimDeviceNotificationManager, SimDevicePasteboard, SimDeviceSet, SimDeviceType, SimRuntime, SimDeviceBootInfo, AXPTranslatorRequest, AXPTranslatorResponse;
@protocol OS_dispatch_queue, OS_dispatch_source, SimDeviceIOProtocol;

@interface SimDevice : NSObject <SimDeviceNotifier>
{
    unsigned long long _state;
    SimDeviceBootInfo *_bootStatus;
    NSString *_name;
    NSString *_runtimeIdentifier;
    NSMachPort *_hostSupportPort;
    NSString *_deviceTypeIdentifier;
    NSUUID *_UDID;
    SimDevicePasteboard *_pasteboard;
    NSObject<SimDeviceIOProtocol> *_io;
    SimDeviceSet *_deviceSet;
    SimDeviceNotificationManager *_notificationManager;
    NSObject<OS_dispatch_queue> *_bootstrapQueue;
    NSMutableDictionary *_registeredServices;
    NSObject<OS_dispatch_queue> *_stateVariableQueue;
    NSMachPort *_deathTriggerPort;
    unsigned long long _pasteboardNotificationRegistrationID;
    NSObject<OS_dispatch_source> *_bootMonitorTimer;
    NSObject<OS_dispatch_queue> *_bootMonitorQueue;
    NSDate *_bootStartedAt;
    NSMutableArray *_darwinNotificationTokens;
    NSDictionary *_bootEnvironmentExtra;
}

+ (BOOL)supportsFeature:(id)arg1 deviceType:(id)arg2 runtime:(id)arg3;
+ (BOOL)isValidState:(unsigned long long)arg1;
+ (id)simDevice:(id)arg1 UDID:(id)arg2 deviceTypeIdentifier:(id)arg3 runtimeIdentifier:(id)arg4 state:(unsigned long long)arg5 deviceSet:(id)arg6;
+ (id)simDeviceAtPath:(id)arg1 deviceSet:(id)arg2;
+ (id)createDeviceWithName:(id)arg1 deviceSet:(id)arg2 deviceType:(id)arg3 runtime:(id)arg4 initialDataPath:(id)arg5;
@property (copy, nonatomic) NSDictionary *bootEnvironmentExtra;
@property (retain, nonatomic) NSMutableArray *darwinNotificationTokens;
@property (retain, nonatomic) NSDate *bootStartedAt;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *bootMonitorQueue;
@property (retain, nonatomic) NSObject<OS_dispatch_source> *bootMonitorTimer;
@property (nonatomic, assign) unsigned long long pasteboardNotificationRegistrationID;
@property (retain, nonatomic) NSMachPort *deathTriggerPort;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *stateVariableQueue;
@property (retain, nonatomic) NSMutableDictionary *registeredServices;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *bootstrapQueue;
@property (retain, nonatomic) SimDeviceNotificationManager *notificationManager;
@property (nonatomic, assign) SimDeviceSet *deviceSet;
@property (retain, nonatomic) NSObject<SimDeviceIOProtocol> *io;
@property (retain, nonatomic) SimDevicePasteboard *pasteboard;
@property (copy, nonatomic) NSUUID *UDID;
@property (copy, nonatomic) NSString *deviceTypeIdentifier;
- (BOOL)bootstrapQueueSync:(CDUnknownBlockType)arg1;
- (void)bootstrapQueueAsync:(CDUnknownBlockType)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)isAvailableWithError:(id *)arg1;
@property (readonly, nonatomic) BOOL available;
- (BOOL)syncUnpairedDevicesWithError:(id *)arg1;
- (BOOL)triggerCloudSyncWithError:(id *)arg1;
- (void)triggerCloudSyncWithCompletionQueue:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (BOOL)darwinNotificationSetState:(unsigned long long)arg1 name:(id)arg2 error:(id *)arg3;
- (BOOL)darwinNotificationGetState:(unsigned long long *)arg1 name:(id)arg2 error:(id *)arg3;
- (BOOL)postDarwinNotification:(id)arg1 error:(id *)arg2;
- (BOOL)terminateApplicationWithID:(NSString *)arg1 error:(NSError **)arg2;
- (int)launchApplicationWithID:(id)arg1 options:(id)arg2 error:(id *)arg3;
- (void)launchApplicationAsyncWithID:(id)arg1 options:(id)arg2 completionQueue:(id)arg3 completionHandler:(void(^)(NSError *, pid_t))arg4;
- (id)installedAppsWithError:(id *)arg1;
- (id)propertiesOfApplication:(id)arg1 error:(id *)arg2;
- (BOOL)applicationIsInstalled:(id)arg1 type:(id *)arg2 error:(id *)arg3;
- (BOOL)uninstallApplication:(id)arg1 withOptions:(id)arg2 error:(id *)arg3;
- (BOOL)installApplication:(id)arg1 withOptions:(id)arg2 error:(id *)arg3;
- (BOOL)setKeyboardLanguage:(id)arg1 error:(id *)arg2;
- (BOOL)addVideo:(NSURL *)path error:(NSError **)arg2;
- (BOOL)addPhoto:(NSURL *)path error:(NSError **)arg2;
- (BOOL)addMedia:(NSArray<NSURL *> *)paths error:(NSError **)arg2;
- (BOOL)openURL:(id)arg1 error:(id *)arg2;
- (id)hostSupportPortWithError:(id *)arg1;
- (long long)compare:(id)arg1;
- (struct NSMutableDictionary *)newDeviceNotification;
- (struct NSMutableDictionary *)createXPCNotification:(id)arg1;
- (struct NSMutableDictionary *)createXPCRequest:(id)arg1;
- (void)handleXPCRequestDeviceIOPortDetachConsumer:(NSDictionary *)arg1;
- (void)handleXPCRequestDeviceIOPortAttachConsumer:(NSDictionary *)arg1;
- (void)handleXPCRequestDeviceIOEnumeratePorts:(NSDictionary *)arg1;
- (void)handleXPCRequestSpawn:(NSDictionary *)arg1;
- (void)handleXPCRequestGetenv:(NSDictionary *)arg1;
- (void)handleXPCRequestLookup:(NSDictionary *)arg1;
- (void)handleXPCRequestUnregister:(NSDictionary *)arg1;
- (void)handleXPCRequestRegister:(NSDictionary *)arg1;
- (void)handleXPCRequestRestore:(NSDictionary *)arg1;
- (void)handleXPCRequestErase:(NSDictionary *)arg1;
- (void)handleXPCRequestUpgrade:(NSDictionary *)arg1;
- (void)handleXPCRequestShutdown:(NSDictionary *)arg1;
- (void)handleXPCRequestBoot:(NSDictionary *)arg1;
- (void)handleXPCRequestRename:(NSDictionary *)arg1;
- (void)handleXPCRequest:(NSDictionary *)arg1;
- (void)handleXPCNotificationDeviceBootStatusChanged:(NSDictionary *)arg1;
- (void)handleXPCNotificationDeviceStateChanged:(NSDictionary *)arg1;
- (void)handleXPCNotification:(NSDictionary *)arg1;
@property (nonatomic, copy, readonly) NSString *runtimeIdentifier;
@property (nonatomic, copy, readonly) NSString *name;
- (SimDeviceBootInfo *)bootStatus;
@property (readonly, nonatomic) unsigned long long state;
- (id)stateString;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(id)arg1 handler:(CDUnknownBlockType)arg2;
- (unsigned long long)registerNotificationHandler:(CDUnknownBlockType)arg1;
- (void)simulateMemoryWarning;
- (id)memoryWarningFilePath;
@property (nonatomic, copy, readonly) NSString *logPath;
- (id)dataPath;
- (id)devicePath;
- (id)environment;
- (int)_spawnFromSelfWithPath:(id)arg1 options:(id)arg2 terminationQueue:(id)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(id *)arg5;
- (int)_spawnFromLaunchdWithPath:(id)arg1 options:(id)arg2 terminationQueue:(id)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(id *)arg5;
- (int)_onBootstrapQueue_spawnWithPath:(id)arg1 options:(id)arg2 terminationQueue:(id)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(id *)arg5;
- (int)spawnWithPath:(id)arg1 options:(id)arg2 terminationQueue:(id)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(id *)arg5;
- (void)spawnAsyncWithPath:(id)arg1 options:(id)arg2 terminationQueue:(id)arg3 terminationHandler:(void (^)(int))arg4 completionQueue:(id)arg5 completionHandler:(void (^)(NSError *, pid_t))arg6;
- (BOOL)unregisterService:(id)arg1 error:(id *)arg2;
- (BOOL)_unregisterService:(id)arg1 error:(id *)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(id)arg2 error:(id *)arg3;
- (BOOL)_registerPort:(unsigned int)arg1 service:(id)arg2 error:(id *)arg3;
- (unsigned int)lookup:(id)arg1 error:(id *)arg2;
- (unsigned int)_lookup:(id)arg1 error:(id *)arg2;
- (id)getenv:(id)arg1 error:(id *)arg2;
- (BOOL)_onBootstrapQueue_restoreContentsAndSettingsFromDevice:(id)arg1 error:(id *)arg2;
- (BOOL)restoreContentsAndSettingsFromDevice:(id)arg1 error:(id *)arg2;
- (void)restoreContentsAndSettingsAsyncFromDevice:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_eraseContentsAndSettingsUsingInitialDataPath:(id)arg1 error:(id *)arg2;
- (BOOL)eraseContentsAndSettingsWithError:(id *)arg1;
- (void)eraseContentsAndSettingsAsyncWithCompletionQueue:(dispatch_queue_t)arg1 completionHandler:(void(^)(NSError *))arg2;
- (BOOL)_onBootstrapQueue_upgradeToRuntime:(id)arg1 error:(id *)arg2;
- (BOOL)upgradeToRuntime:(id)arg1 error:(id *)arg2;
- (void)upgradeAsyncToRuntime:(id)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_rename:(id)arg1 error:(id *)arg2;
- (BOOL)rename:(id)arg1 error:(id *)arg2;
- (void)renameAsync:(id)arg1 completionQueue:(id)arg2 completetionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_shutdownIOAndNotifyWithError:(id *)arg1;
- (BOOL)_onBootstrapQueue_shutdownWithError:(id *)arg1;
- (BOOL)shutdownWithError:(id *)arg1;
- (void)shutdownAsyncWithCompletionQueue:(id)arg1 completionHandler:(void(^)(NSError *))arg2;
- (BOOL)_sendBridgeRequest:(CDUnknownBlockType)arg1 error:(id *)arg2;
- (void)_onBootMonitorQueue_bootStatusTimerFired;
- (BOOL)_onBootstrapQueue_bootWithOptions:(id)arg1 deathMonitorPort:(id)arg2 deathTriggerPort:(id)arg3 error:(id *)arg4;
- (BOOL)_onBootstrapQueue_bootWithOptions:(id)arg1 error:(id *)arg2;
- (BOOL)bootWithOptions:(id)arg1 error:(id *)arg2;
- (void)bootAsyncWithOptions:(id)arg1 completionQueue:(id)arg2 completionHandler:(void(^)(NSError *))arg3;
- (void)launchdDeathHandlerWithDeathPort:(id)arg1;
- (BOOL)startLaunchdWithDeathPort:(id)arg1 deathHandler:(CDUnknownBlockType)arg2 error:(id *)arg3;
- (void)registerPortsWithLaunchd;
@property (nonatomic, copy, readonly) NSArray *launchDaemonsPaths;
- (BOOL)removeLaunchdJobWithError:(id *)arg1;
- (BOOL)createLaunchdJobWithError:(id *)arg1 extraEnvironment:(id)arg2 disabledJobs:(id)arg3;
- (BOOL)createDarwinNotificationProxiesWithError:(id *)arg1;
- (BOOL)createDarwinNotificationProxy:(id)arg1 toSimAs:(id)arg2 withState:(BOOL)arg3 error:(id *)arg4;
- (BOOL)clearTmpWithError:(id *)arg1;
- (BOOL)ensureLogPathsWithError:(id *)arg1;
- (BOOL)supportsFeature:(id)arg1;
@property (nonatomic, copy, readonly) NSString *launchdJobName;
- (void)saveToDisk;
- (id)saveStateDict;
- (void)validateAndFixStateUsingInitialDataPath:(id)arg1;
@property (readonly, nonatomic) SimRuntime *runtime;
@property (readonly, nonatomic) SimDeviceType *deviceType;
@property (nonatomic, copy, readonly) NSString *descriptiveName;
- (id)description;
- (void)dealloc;
- (BOOL)_onBootstrapQueue_initializeDeviceIO:(id *)arg1;
- (id)initDevice:(id)arg1 UDID:(id)arg2 deviceTypeIdentifier:(id)arg3 runtimeIdentifier:(id)arg4 state:(unsigned long long)arg5 initialDataPath:(id)arg6 deviceSet:(id)arg7;
- (void)triggerCloudSyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)launchApplicationAsyncWithID:(id)arg1 options:(id)arg2 completionHandler:(void(^)(NSError *, pid_t))arg3;
- (int)spawnWithPath:(id)arg1 options:(id)arg2 terminationHandler:(CoreSimulatorAgentTerminationHandler)arg3 error:(id *)arg4;
- (void)spawnAsyncWithPath:(id)arg1 options:(id)arg2 terminationHandler:(CoreSimulatorAgentTerminationHandler)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (void)restoreContentsAndSettingsAsyncFromDevice:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)eraseContentsAndSettingsAsyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)renameAsync:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)shutdownAsyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)bootAsyncWithOptions:(id)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (BOOL)unpairIDSRelayWithDevice:(id)arg1 error:(id *)arg2;
- (BOOL)setActiveIDSRelayDevice:(id)arg1 error:(id *)arg2;
- (BOOL)disconnectIDSRelayToDevice:(id)arg1 error:(id *)arg2;
- (BOOL)connectIDSRelayToDevice:(id)arg1 disconnectMonitorPort:(unsigned int *)arg2 error:(id *)arg3;

// In Xcode 12, this replaces SimulatorBridge related accessibility requests .

- (void)sendAccessibilityRequestAsync:(AXPTranslatorRequest *)request completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(AXPTranslatorResponse *))completionHandler;
- (NSString *)accessibilityPlatformTranslationToken;
- (id)accessibilityConnection;

// Privacy commands

- (BOOL)setPrivacyAccessForService:(NSString *)service bundleID:(NSString *)bundleID granted:(BOOL)granted error:(NSError **)error;

- (BOOL)resetPrivacyAccessForService:(NSString *)service bundleID:(NSString *)bundleID error:(NSError **)error;

@end

