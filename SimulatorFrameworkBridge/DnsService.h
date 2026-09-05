/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Configures the simulator's DNS by writing configd_sim's `State:/Network/Global/DNS`, which every
 * resolver lookup (NSURLSession, NWConnection, getaddrinfo) reads. Actions: `set <server>...`, `clear`,
 * `list` (prints JSON). Returns 0 on success.
 */
int handleDnsAction(NSString *action, NSArray<NSString *> *arguments);

NSDictionary<NSString *, id> *buildDnsDict(NSArray<NSString *> *servers);

NSDictionary<NSString *, id> *buildEmptyDnsDict(void);

NS_ASSUME_NONNULL_END
