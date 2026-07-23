/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimRuntime.h>

@interface SimRuntime (Removed)

/**
 Removed in Xcode 8.1
 */
+ (NSArray<SimRuntime *> *)supportedRuntimes;

/**
 Removed in Xcode 27 (CoreSimulator 1155.4). The libLaunch host trampolines
 (launch_sim_*), the platform-overlay / dyld_sim path accessors, and the
 bundle/path initializers are gone. Not called by idb/FBSimulatorControl.
 */
- (id)platformRuntimeOverlay;
- (CDUnknownFunctionPointerType)launch_sim_set_death_handler;
- (CDUnknownFunctionPointerType)launch_sim_waitpid;
- (CDUnknownFunctionPointerType)launch_sim_spawn;
- (CDUnknownFunctionPointerType)launch_sim_getenv;
- (CDUnknownFunctionPointerType)launch_sim_bind_session_to_port;
- (CDUnknownFunctionPointerType)launch_sim_find_endpoint;
- (CDUnknownFunctionPointerType)launch_sim_unregister_endpoint;
- (CDUnknownFunctionPointerType)launch_sim_register_endpoint;
- (id)dyld_simPath;
- (id)initWithBundle:(id)arg1;
- (id)initWithPath:(id)arg1;

@end
