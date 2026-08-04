/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Test-only surface for `AccessibilityService`. These declarations reach internals of
 * `AccessibilityService.m` so `SimulatorFrameworkBridgeLibTests` can pin the guest↔host wire contract
 * and cover modal detection without a live in-guest accessibility runtime. Not part of the service's
 * production API.
 */

/**
 * A snapshot of the guest's file-scope wire-key constants, keyed by a stable semantic name (e.g.
 * `node.elementType`, `envelope.ok`, `modal.kind`). The guest and host each hold their own copy of these
 * strings with no shared header, so a test asserts each guest constant equals the byte-identical literal
 * the host pins — that cross-file agreement is the wire-contract enforcement. Exposing the values through
 * one accessor keeps the constants file-local rather than giving each external linkage.
 */
NSDictionary<NSString *, NSString *> *FBAXBridgeWireConstantsForTesting(void);

/**
 * Builds the fullscreen-modal descriptor for a built `XC_kAXXC*`-keyed attribute tree, or nil when
 * neither a system (`SBAlertItemWindow`) nor an app (`_UIAlertController*`) alert is present. The
 * descriptor carries `kind` (`system`/`app`), `elementType`, and an optional `label` — the same `modal`
 * enrichment a describe response puts on the wire.
 */
NSDictionary<NSString *, NSString *> *_Nullable FBAXBridgeModalDescriptor(NSDictionary<NSString *, id> *tree);

NS_ASSUME_NONNULL_END
