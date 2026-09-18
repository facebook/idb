/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if __has_include(<SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>)
 #import <SimulatorFrameworkBridgeRuntime/NetworkConfigurationStore.h>
 #import <SimulatorFrameworkBridgeRuntime/NotificationSettingsClient.h>
#else
 #import "Runtime/NetworkConfigurationStore.h"
 #import "Runtime/NotificationSettingsClient.h"
#endif
#import "ServiceDispatch.h"
