/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

+ (BOOL)supportsFeature:(NSString *)arg1 deviceType:(SimDeviceType *)arg2 runtime:(SimRuntime *)arg3;
+ (BOOL)isValidState:(unsigned long long)arg1;
+ (instancetype)simDevice:(NSString *)arg1 UDID:(NSUUID *)arg2 deviceTypeIdentifier:(NSString *)arg3 runtimeIdentifier:(NSString *)arg4 runtimePolicy:(NSString *)arg5 runtimeSpecifier:(NSString *)arg6 state:(unsigned long long)arg7 lastBootedAt:(NSDate *)arg8 deviceSet:(SimDeviceSet *)arg9;
+ (instancetype)simDeviceAtPath:(NSString *)arg1 deviceSet:(SimDeviceSet *)arg2;
+ (instancetype)createDeviceWithName:(NSString *)arg1 deviceSet:(SimDeviceSet *)arg2 deviceType:(SimDeviceType *)arg3 runtime:(SimRuntime *)arg4 initialDataPath:(NSString *)arg5 error:(NSError **)arg6;
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
- (void)bootstrapQueueAsync:(CDUnknownBlockType)arg1 completionQueue:(dispatch_queue_t)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)isAvailableWithError:(NSError **)arg1;
@property (readonly, nonatomic) BOOL available;
- (BOOL)syncUnpairedDevicesWithError:(NSError **)arg1;
- (BOOL)triggerCloudSyncWithError:(NSError **)arg1;
- (void)triggerCloudSyncWithCompletionQueue:(dispatch_queue_t)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (BOOL)darwinNotificationSetState:(unsigned long long)arg1 name:(NSString *)arg2 error:(NSError **)arg3;
- (BOOL)darwinNotificationGetState:(unsigned long long *)arg1 name:(NSString *)arg2 error:(NSError **)arg3;
- (BOOL)postDarwinNotification:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)terminateApplicationWithID:(NSString *)arg1 error:(NSError **)arg2;
- (int)launchApplicationWithID:(NSString *)arg1 options:(NSDictionary *)arg2 error:(NSError **)arg3;
- (void)launchApplicationAsyncWithID:(NSString *)arg1 options:(NSDictionary *)arg2 completionQueue:(dispatch_queue_t)arg3 completionHandler:(void(^)(NSError *, pid_t))arg4;
- (NSDictionary *)installedAppsWithError:(NSError **)arg1;
- (NSDictionary<NSString *, id> *)propertiesOfApplication:(NSString *)bundleID error:(NSError **)error;
- (BOOL)applicationIsInstalled:(NSString *)bundleID type:(NSString **)typeOut error:(NSError **)error;
- (BOOL)uninstallApplication:(NSString *)arg1 withOptions:(NSDictionary *)arg2 error:(NSError **)arg3;
- (BOOL)installApplication:(NSURL *)arg1 withOptions:(NSDictionary *)arg2 error:(NSError **)arg3;
- (BOOL)setKeyboardLanguage:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)addVideo:(NSURL *)path error:(NSError **)arg2;
- (BOOL)addPhoto:(NSURL *)path error:(NSError **)arg2;
- (BOOL)addMedia:(NSArray<NSURL *> *)paths error:(NSError **)arg2;
- (BOOL)openURL:(NSURL *)arg1 error:(NSError **)arg2;
- (NSUUID *)hostSupportPortWithError:(NSError **)arg1;
- (long long)compare:(SimDevice *)arg1;
- (NSMutableDictionary *)newDeviceNotification;
- (NSMutableDictionary *)createXPCNotification:(NSDictionary *)arg1;
- (NSMutableDictionary *)createXPCRequest:(NSDictionary *)arg1;
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
- (NSString *)stateString;
- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(NSError **)arg2;
- (unsigned long long)registerNotificationHandlerOnQueue:(dispatch_queue_t)arg1 handler:(CDUnknownBlockType)arg2;
- (unsigned long long)registerNotificationHandler:(CDUnknownBlockType)arg1;
- (void)simulateMemoryWarning;
- (NSString *)memoryWarningFilePath;
@property (nonatomic, copy, readonly) NSString *logPath;
- (NSString *)dataPath;
- (NSString *)devicePath;
- (NSDictionary *)environment;
- (int)_spawnFromSelfWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationQueue:(dispatch_queue_t)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(NSError **)arg5;
- (int)_spawnFromLaunchdWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationQueue:(dispatch_queue_t)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(NSError **)arg5;
- (int)_onBootstrapQueue_spawnWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationQueue:(dispatch_queue_t)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(NSError **)arg5;
- (int)spawnWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationQueue:(dispatch_queue_t)arg3 terminationHandler:(CDUnknownBlockType)arg4 error:(NSError **)arg5;
- (void)spawnAsyncWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationQueue:(dispatch_queue_t)arg3 terminationHandler:(void (^)(int))arg4 completionQueue:(dispatch_queue_t)arg5 completionHandler:(void (^)(NSError *, pid_t))arg6;
- (BOOL)unregisterService:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)_unregisterService:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(NSString *)arg2 error:(NSError **)arg3;
- (BOOL)_registerPort:(unsigned int)arg1 service:(NSString *)arg2 error:(NSError **)arg3;
- (unsigned int)lookup:(NSString *)arg1 error:(NSError **)arg2;
- (unsigned int)_lookup:(NSString *)arg1 error:(NSError **)arg2;
- (NSString *)getenv:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)_onBootstrapQueue_restoreContentsAndSettingsFromDevice:(SimDevice *)arg1 error:(NSError **)arg2;
- (BOOL)restoreContentsAndSettingsFromDevice:(SimDevice *)arg1 error:(NSError **)arg2;
- (void)restoreContentsAndSettingsAsyncFromDevice:(SimDevice *)arg1 completionQueue:(dispatch_queue_t)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_eraseContentsAndSettingsUsingInitialDataPath:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)eraseContentsAndSettingsWithError:(NSError **)arg1;
- (void)eraseContentsAndSettingsAsyncWithCompletionQueue:(dispatch_queue_t)arg1 completionHandler:(void(^)(NSError *))arg2;
- (BOOL)_onBootstrapQueue_upgradeToRuntime:(SimRuntime *)arg1 error:(NSError **)arg2;
- (BOOL)upgradeToRuntime:(SimRuntime *)arg1 error:(NSError **)arg2;
- (void)upgradeAsyncToRuntime:(SimRuntime *)arg1 completionQueue:(dispatch_queue_t)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_rename:(NSString *)arg1 error:(NSError **)arg2;
- (BOOL)rename:(NSString *)arg1 error:(NSError **)arg2;
- (void)renameAsync:(NSString *)arg1 completionQueue:(dispatch_queue_t)arg2 completetionHandler:(CDUnknownBlockType)arg3;
- (BOOL)_onBootstrapQueue_shutdownIOAndNotifyWithError:(NSError **)arg1;
- (BOOL)_onBootstrapQueue_shutdownWithError:(NSError **)arg1;
- (BOOL)shutdownWithError:(NSError **)arg1;
- (void)shutdownAsyncWithCompletionQueue:(dispatch_queue_t)arg1 completionHandler:(void(^)(NSError *))arg2;
- (BOOL)_sendBridgeRequest:(CDUnknownBlockType)arg1 error:(NSError **)arg2;
- (void)_onBootMonitorQueue_bootStatusTimerFired;
- (BOOL)_onBootstrapQueue_bootWithOptions:(NSDictionary *)arg1 deathMonitorPort:(NSMachPort *)arg2 deathTriggerPort:(NSMachPort *)arg3 error:(NSError **)arg4;
- (BOOL)_onBootstrapQueue_bootWithOptions:(NSDictionary *)arg1 error:(NSError **)arg2;
- (BOOL)bootWithOptions:(NSDictionary *)arg1 error:(NSError **)arg2;
- (void)bootAsyncWithOptions:(NSDictionary *)arg1 completionQueue:(dispatch_queue_t)arg2 completionHandler:(void(^)(NSError *))arg3;
- (void)launchdDeathHandlerWithDeathPort:(NSMachPort *)arg1;
- (BOOL)startLaunchdWithDeathPort:(NSMachPort *)arg1 deathHandler:(CDUnknownBlockType)arg2 error:(NSError **)arg3;
- (void)registerPortsWithLaunchd;
@property (nonatomic, copy, readonly) NSArray *launchDaemonsPaths;
- (BOOL)removeLaunchdJobWithError:(NSError **)arg1;
- (BOOL)createLaunchdJobWithBinpref:(NSUInteger)arg1 enableCheckedAllocations:(BOOL)arg2 extraEnvironment:(NSDictionary *)arg3 disabledJobs:(NSDictionary *)arg4 error:(NSError **)arg5;
- (BOOL)createDarwinNotificationProxiesWithError:(NSError **)arg1;
- (BOOL)createDarwinNotificationProxy:(NSString *)arg1 toSimAs:(NSString *)arg2 withState:(BOOL)arg3 error:(NSError **)arg4;
- (BOOL)clearTmpWithError:(NSError **)arg1;
- (BOOL)ensureLogPathsWithError:(NSError **)arg1;
- (BOOL)supportsFeature:(NSString *)arg1;
@property (nonatomic, copy, readonly) NSString *launchdJobName;
- (void)saveToDisk;
- (NSDictionary *)saveStateDict;
- (void)validateAndFixStateUsingInitialDataPath:(NSString *)arg1;
@property (readonly, nonatomic) SimRuntime *runtime;
@property (readonly, nonatomic) SimDeviceType *deviceType;
@property (nonatomic, copy, readonly) NSString *descriptiveName;
- (NSString *)description;
- (void)dealloc;
- (BOOL)_onBootstrapQueue_initializeDeviceIO:(NSError **)arg1;
- (instancetype)initDevice:(NSString *)arg1 UDID:(NSUUID *)arg2 deviceTypeIdentifier:(NSString *)arg3 runtimeIdentifier:(NSString *)arg4 runtimePolicy:(NSString *)arg5 runtimeSpecifier:(NSString *)arg6 state:(unsigned long long)arg7 initialDataPath:(NSString *)arg8 preparingForDeletion:(BOOL)arg9 isEphemeral:(BOOL)arg10 lastBootedAt:(NSDate *)arg11 deviceSet:(SimDeviceSet *)arg12;
- (void)triggerCloudSyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)launchApplicationAsyncWithID:(NSString *)arg1 options:(NSDictionary *)arg2 completionHandler:(void(^)(NSError *, pid_t))arg3;
- (int)spawnWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationHandler:(CoreSimulatorAgentTerminationHandler)arg3 error:(NSError **)arg4;
- (void)spawnAsyncWithPath:(NSString *)arg1 options:(NSDictionary *)arg2 terminationHandler:(CoreSimulatorAgentTerminationHandler)arg3 completionHandler:(CDUnknownBlockType)arg4;
- (void)restoreContentsAndSettingsAsyncFromDevice:(SimDevice *)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)eraseContentsAndSettingsAsyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)renameAsync:(NSString *)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (void)shutdownAsyncWithCompletionHandler:(CDUnknownBlockType)arg1;
- (void)bootAsyncWithOptions:(NSDictionary *)arg1 completionHandler:(CDUnknownBlockType)arg2;
- (id)setHardwareKeyboardEnabled:(_Bool)arg1 keyboardType:(unsigned char)arg2 error:(NSError **)arg3;

// In Xcode 12, this replaces SimulatorBridge related accessibility requests.

- (void)sendAccessibilityRequestAsync:(AXPTranslatorRequest *)request completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(AXPTranslatorResponse *))completionHandler;
- (NSString *)accessibilityPlatformTranslationToken;
- (id)accessibilityConnection;

@end

#pragma mark - Categories
// The following categories are declared on SimDevice in CoreSimulator.framework.
// All use the host_support MIG protocol via CoreSimulatorBridge unless noted.
// Dumped from CoreSimulator.framework in Xcode 26.2.

/**
 Dynamic Type and Increase Contrast.
 Equivalent to `simctl ui <device> content_size` and `simctl ui <device> increase_contrast`.
 */
@interface SimDevice (Accessibility)
/// Returns a raw NSInteger: content size category index (1-12). See FBSimulatorContentSizeCategory.
- (NSInteger)currentContentSizeCategory;
/// Accepts a raw NSInteger: content size category index (1-12). See FBSimulatorContentSizeCategory.
- (BOOL)setContentSizeCategory:(NSInteger)category error:(NSError **)error;
- (id)currentIncreaseContrastMode;
- (BOOL)setIncreaseContrastEnabled:(BOOL)enabled error:(NSError **)error;
@end

/**
 Dark/Light mode appearance.
 Equivalent to `simctl ui <device> appearance`.
 */
@interface SimDevice (SimUIInterfaceStyle)
/// Returns a raw NSInteger: 1 = Light, 2 = Dark (UIUserInterfaceStyle values).
- (NSInteger)currentUIInterfaceStyle;
/// Accepts a raw NSInteger: 1 = Light, 2 = Dark (UIUserInterfaceStyle values).
- (BOOL)setUIInterfaceStyle:(NSInteger)style error:(NSError **)error;
@end

/**
 Status bar overrides for deterministic screenshots.
 Equivalent to `simctl status_bar <device> override/clear/list`.
 All parameters are raw NSInteger values (same pattern as UIInterfaceStyle and ContentSizeCategory)
 except timeString and operatorName which are genuine NSString *.
 Integer mappings confirmed via xcrun simctl status_bar on Xcode 26.2.
 */
@interface SimDevice (StatusBarOverrides)
- (BOOL)overrideStatusBarTimeString:(NSString *)timeString error:(NSError **)error;
/// dataNetworkType: 0=hide, 1=wifi, 6=3g, 7=4g, 8=lte, 9=lte-a, 10=lte+, 11=5g, 12=5g+, 13=5g-uwb, 14=5g-uc. Integers 2-5 are unused legacy gaps.
- (BOOL)overrideStatusBarDataNetworkType:(NSInteger)networkType error:(NSError **)error;
/// wiFiMode: 1=searching, 2=failed, 3=active. bars: 0-3.
- (BOOL)overrideStatusBarWiFiMode:(NSInteger)mode bars:(NSInteger)bars error:(NSError **)error;
/// cellularMode: 0=notSupported, 1=searching, 2=failed, 3=active. operatorName: NSString *. bars: 0-4.
- (BOOL)overrideStatusBarCellularMode:(NSInteger)mode operatorName:(NSString *)operatorName bars:(NSInteger)bars error:(NSError **)error;
/// batteryState: 0=discharging, 1=charging, 2=charged. batteryLevel: 0-100.
- (BOOL)overrideStatusBarBatteryState:(NSInteger)batteryState batteryLevel:(NSInteger)level showNotCharging:(BOOL)showNotCharging error:(NSError **)error;
/// Clears status bar overrides. `flags` is sent as @{@"OverridesToClear": @(flags)} via MIG.
/// Bit 31 (0x80000000) = clear all. Pass NSUIntegerMax to clear everything. Values < 0x80000000 are no-ops.
/// NOTE: Class-dump shows 1-arg `clearStatusBarOverrides:` — actual runtime selector is 2-arg `clearStatusBarOverrides:error:`.
- (BOOL)clearStatusBarOverrides:(NSUInteger)flags error:(NSError **)error;
/// All out-params are id * — the method deserializes a MIG dictionary and stores dict[@"Key"] to each.
/// Strings (timeString, operatorName) return NSString *. Numbers return NSNumber *. showNotCharging returns NSNumber * (boolean).
- (BOOL)currentStatusBarOverridesForTimeString:(NSString **)timeString dataNetworkType:(NSNumber **)networkType wiFiMode:(NSNumber **)wiFiMode wiFiBars:(NSNumber **)wiFiBars cellularMode:(NSNumber **)cellularMode operatorName:(NSString **)operatorName cellularBars:(NSNumber **)cellularBars batteryState:(NSNumber **)batteryState batteryLevel:(NSNumber **)batteryLevel showNotCharging:(NSNumber **)showNotCharging error:(NSError **)error;
@end

/**
 Keychain management.
 Uses host_support_mig_reset_keychain MIG call — same as `simctl keychain reset`.
 */
@interface SimDevice (SimDeviceKeychain)
- (BOOL)resetKeychainWithError:(NSError **)error;
- (BOOL)addCertificateAtURL:(NSURL *)url trustAsRoot:(BOOL)trustAsRoot error:(NSError **)error;
@end

/**
 Location simulation.
 Equivalent to `simctl location <device> set/clear/start/run/list`.
 */
@interface SimDevice (SimLocation)
- (id)availableLocationScenarios;
- (BOOL)setLocationWithLatitude:(double)latitude andLongitude:(double)longitude error:(NSError **)error;
- (BOOL)setLocationScenario:(NSString *)scenario error:(NSError **)error;
- (BOOL)setLocationScenarioWithPath:(NSString *)path error:(NSError **)error;
- (BOOL)startLocationSimulationWithDistance:(double)distance speed:(double)speed waypoints:(NSArray *)waypoints error:(NSError **)error;
- (BOOL)startLocationSimulationWithInterval:(double)interval speed:(double)speed waypoints:(NSArray *)waypoints error:(NSError **)error;
- (BOOL)clearSimulatedLocationWithError:(NSError **)error;
@end

/**
 TCC privacy grant/reset.
 Equivalent to `simctl privacy <device> grant/revoke/reset`.
 Service names use kTCCService* constants (e.g. @"kTCCServiceCamera") or
 __CoreLocation* prefixes (e.g. @"__CoreLocationAlways", @"__CoreLocationWhenInUse").
 */
@interface SimDevice (SimPrivacyAccess)
- (BOOL)setPrivacyAccessForService:(NSString *)service bundleID:(NSString *)bundleID granted:(BOOL)granted error:(NSError **)error;
- (BOOL)resetPrivacyAccessForService:(NSString *)service bundleID:(NSString *)bundleID error:(NSError **)error;
@end

/**
 Push notification simulation.
 Equivalent to `simctl push <device> <bundleID> <payload.json>`.
 */
@interface SimDevice (SimPushNotification)
- (void)sendPushNotificationForBundleID:(NSString *)bundleID jsonPayload:(NSDictionary *)jsonPayload error:(NSError **)error;
@end

/**
 Runtime feature availability checks.
 */
@interface SimDevice (SimOSFeatures)
- (BOOL)isOSFeatureEnabled:(NSString *)featureName domain:(NSString *)domain;
@end

/**
 Core Animation debug overlays (flash on redraw, color blended layers, etc.).
 */
@interface SimDevice (SimCADebugOption)
- (id)getCADebugOption:(NSString *)optionName;
- (BOOL)setCADebugOption:(NSString *)optionName enabled:(BOOL)enabled;
@end

/**
 Display backlight control.
 */
@interface SimDevice (SimDisplayBacklight)
- (BOOL)setDisplayBacklightActive:(BOOL)active error:(NSError **)error;
@end

/**
 Nearby Interaction device simulation (spatial tracking).
 */
@interface SimDevice (SimNearbyDevices)
- (BOOL)updateNearbyInteractionDeviceRect:(CGRect)rect deviceRotation:(double)rotation error:(NSError **)error;
@end

/**
 watchOS device pairing via IDS Relay.
 */
@interface SimDevice (PairingSupport)
- (BOOL)connectIDSRelayToDevice:(SimDevice *)device disconnectMonitorPort:(unsigned int *)port error:(NSError **)error;
- (BOOL)disconnectIDSRelayToDevice:(SimDevice *)device error:(NSError **)error;
- (BOOL)setActiveIDSRelayDevice:(SimDevice *)device error:(NSError **)error;
- (BOOL)unpairIDSRelayWithDevice:(SimDevice *)device error:(NSError **)error;
@end

