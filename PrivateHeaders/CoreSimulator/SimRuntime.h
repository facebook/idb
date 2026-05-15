/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSBundle, NSDictionary, NSString, SimRuntimePairingReuirements;

@interface SimRuntime : NSObject
{
  unsigned int _version;
  unsigned int _equivalentIOSVersion;
  unsigned int _minHostVersion;
  unsigned int _maxHostVersion;
  unsigned int _minCoreSimulatorFrameworkVersion;
  unsigned int _maxCoreSimulatorFrameworkVersion;
  NSString *_name;
  NSString *_identifier;
  NSBundle *_bundle;
  NSString *_root;
  NSString *_versionString;
  NSString *_buildVersionString;
  NSString *_platformIdentifier;
  NSDictionary *_supportedFeatures;
  NSDictionary *_supportedFeaturesConditionalOnDeviceType;
  NSDictionary *_requiredHostServices;
  NSDictionary *_forwardHostNotifications;
  NSDictionary *_forwardHostNotificationsWithState;
  NSString *_platformPath;
  NSArray *_supportedProductFamilyIDs;
  SimRuntimePairingReuirements *_pairingRequirements;
  NSArray *_preferredPairingDeviceTypes;
  NSDictionary *_environment_extra;
  void *_libLaunchHostHandle;
  NSArray *_aliases;
}

+ (unsigned int)equivalentIOSVersionForVersion:(unsigned int)arg1 profile:(id)arg2 platformIdentifier:(id)arg3;
+ (id)updatedMaxCoreSimulatorVersions;
+ (id)updatedMaxHostVersions;
@property (nonatomic, assign) unsigned int maxCoreSimulatorFrameworkVersion;
@property (nonatomic, assign) unsigned int minCoreSimulatorFrameworkVersion;
@property (nonatomic, assign) unsigned int maxHostVersion;
@property (nonatomic, assign) unsigned int minHostVersion;
@property (nonatomic, copy) NSArray *aliases;
@property (nonatomic, assign) void *libLaunchHostHandle;
@property (nonatomic, copy) NSDictionary *environment_extra;
@property (nonatomic, copy) NSArray *preferredPairingDeviceTypes;
@property (nonatomic, retain) SimRuntimePairingReuirements *pairingRequirements;
@property (nonatomic, copy) NSArray *supportedProductFamilyIDs;
@property (nonatomic, copy) NSString *platformPath;
@property (nonatomic, copy) NSDictionary *forwardHostNotificationsWithState;
@property (nonatomic, copy) NSDictionary *forwardHostNotifications;
@property (nonatomic, copy) NSDictionary *requiredHostServices;
@property (nonatomic, copy) NSDictionary *supportedFeaturesConditionalOnDeviceType;
@property (nonatomic, copy) NSDictionary *supportedFeatures;
@property (nonatomic, assign) unsigned int equivalentIOSVersion;
@property (nonatomic, assign) unsigned int version;
@property (nonatomic, copy) NSString *platformIdentifier;
@property (nonatomic, copy) NSString *buildVersionString;
@property (nonatomic, copy) NSString *versionString;
@property (nonatomic, copy) NSString *root;
@property (nonatomic, retain) NSBundle *bundle;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;

- (id)platformRuntimeOverlay;
- (CDUnknownFunctionPointerType)launch_sim_set_death_handler;
- (CDUnknownFunctionPointerType)launch_sim_waitpid;
- (CDUnknownFunctionPointerType)launch_sim_spawn;
- (CDUnknownFunctionPointerType)launch_sim_getenv;
- (CDUnknownFunctionPointerType)launch_sim_bind_session_to_port;
- (CDUnknownFunctionPointerType)launch_sim_find_endpoint;
- (CDUnknownFunctionPointerType)launch_sim_unregister_endpoint;
- (CDUnknownFunctionPointerType)launch_sim_register_endpoint;
- (BOOL)isAvailableWithError:(id *)arg1;
@property (nonatomic, readonly) BOOL available;
- (id)dyld_simPath;
- (BOOL)createInitialContentPath:(id)arg1 error:(id *)arg2;
- (id)sampleContentPath;
- (long long)compare:(id)arg1;
- (BOOL)supportsFeatureConditionally:(id)arg1;
- (BOOL)supportsFeature:(id)arg1;
- (BOOL)supportsDeviceType:(id)arg1;
- (id)environment;
- (id)description;
- (id)initWithBundle:(id)arg1;
- (id)initWithPath:(id)arg1;

@end
