/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Reads and writes one raw configd_sim key, for tests that need the store as it is rather than as a
 * service interprets it. Actions: `snapshot <key>` writes a binary property list of
 * `{present: BOOL, value: <the value>}` to stdout; `restore <key>` reads that same plist from stdin,
 * puts the key back the way it describes -- removing it where `present` is false -- and writes the
 * resulting snapshot to stdout. `<key>` is a configd key such as `State:/Network/Global/DNS`, or one
 * of the `dns` and `proxy` aliases for the two global keys. Returns 0 on success.
 *
 * Nothing but the plist is written to stdout, so a caller can read the value back byte for byte.
 */
int handleDynamicStoreAction(NSString *action, NSArray<NSString *> *arguments);

/** The configd key an argument names: the argument itself, or the key one of the aliases stands for. */
NSString *_Nullable dynamicStoreKeyForName(NSString *name);

NS_ASSUME_NONNULL_END
