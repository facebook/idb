/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#if __has_include(<SimulatorFrameworkBridgeRuntime/AccessibilityRuntime.h>)
 #import <SimulatorFrameworkBridgeRuntime/AccessibilityRuntime.h>
#else
 #import "Runtime/AccessibilityRuntime.h"
#endif

NS_ASSUME_NONNULL_BEGIN

/** Guest wire constants keyed by stable semantic names for host/guest contract tests. */
NSDictionary<NSString *, NSString *> *FBAXBridgeWireConstantsForTesting(void);

/** Returns the fullscreen modal descriptor derived from an accessibility tree. */
NSDictionary<NSString *, NSString *> *_Nullable FBAXBridgeModalDescriptor(NSDictionary<NSString *, id> *tree);

/** Substitutes a runtime for tests, or restores the live runtime when passed nil. */
void FBAXBridgeSetRuntimeForTesting(id<FBAXRuntime> _Nullable runtime);

/** Substitutes initialization without sharing the production dispatch-once state. */
void FBAXBridgeSetRuntimeFactoryForTesting(FBAXRuntimeFactory _Nullable factory);

NS_ASSUME_NONNULL_END
