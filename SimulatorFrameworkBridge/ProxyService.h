/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Configures the simulator's network proxy by writing configd_sim's SCDynamicStore proxies key, which
 * every networking API (NSURLSession, NWConnection, CFNetwork) honours without app-side changes.
 * Actions: `set <host> <port> [http|socks]`, `clear`, `list` (prints JSON). Returns 0 on success.
 */
int handleProxyAction(NSString *action, NSArray<NSString *> *arguments);

NSDictionary<NSString *, id> *buildHTTPProxyDict(NSString *host, int port);

NSDictionary<NSString *, id> *buildSOCKSProxyDict(NSString *host, int port);

NSDictionary<NSString *, id> *buildEmptyProxyDict(void);

NS_ASSUME_NONNULL_END
