/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "AccessibilityRuntime.h"

NS_ASSUME_NONNULL_BEGIN

/** Guest wire constants keyed by stable semantic names for host/guest contract tests. */
NSDictionary<NSString *, NSString *> *FBAXBridgeWireConstantsForTesting(void);

/** The Unix-socket listen backlog. */
int FBAXBridgeServeBacklogForTesting(void);

/** Parses the serve idle timeout from flag/value arguments. */
int FBAXBridgeIdleTimeoutForTesting(NSArray<NSString *> *arguments, int fallback);

/** The serve idle timeout used when no argument is present. */
int FBAXBridgeDefaultIdleTimeoutForTesting(void);

/** Parses whether serve mode exits when its client disconnects. */
BOOL FBAXBridgeExitOnDisconnectForTesting(NSArray<NSString *> *arguments);

/** Returns the fullscreen modal descriptor derived from an accessibility tree. */
NSDictionary<NSString *, NSString *> *_Nullable FBAXBridgeModalDescriptor(NSDictionary<NSString *, id> *tree);

/** Substitutes a runtime for tests, or restores the live runtime when passed nil. */
void FBAXBridgeSetRuntimeForTesting(id<FBAXRuntime> _Nullable runtime);

NS_ASSUME_NONNULL_END
