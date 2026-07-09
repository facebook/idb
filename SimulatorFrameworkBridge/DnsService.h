/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Configures per-simulator DNS settings by writing directly to
 * configd_sim's SCDynamicStore at key State:/Network/Global/DNS.
 *
 * DNS changes affect all resolver lookups within the simulator —
 * NSURLSession, NWConnection, getaddrinfo, etc. all read from
 * configd_sim's DNS configuration.
 *
 * Uses the same dlsym pattern as ProxyService for loading
 * SCDynamicStore functions at runtime.
 *
 * Usage:
 *   handleDnsAction(@"set", @[@"8.8.8.8", @"8.8.4.4"])  // Set DNS servers
 *   handleDnsAction(@"clear", @[])                       // Clear DNS config
 *   handleDnsAction(@"list", @[])                        // Print current config as JSON
 *
 * @param action "set", "clear", or "list"
 * @param arguments For "set": [server1, server2, ...]. For "clear"/"list": empty.
 * @return 0 on success, 1 on failure
 */
int handleDnsAction(NSString *action, NSArray<NSString *> *arguments);

/**
 * Builds an NSDictionary containing DNS server configuration.
 *
 * @param servers Array of DNS server addresses (e.g. @[@"8.8.8.8", @"8.8.4.4"])
 * @return An NSDictionary with ServerAddresses key
 */
NSDictionary<NSString *, id> *buildDnsDict(NSArray<NSString *> *servers);

/**
 * Builds an empty NSDictionary that clears DNS configuration.
 *
 * @return An empty NSDictionary
 */
NSDictionary<NSString *, id> *buildEmptyDnsDict(void);

NS_ASSUME_NONNULL_END
