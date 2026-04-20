/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Configures per-simulator network proxy settings by writing directly
 * to configd_sim's SCDynamicStore. This is transparent to all networking
 * APIs — NSURLSession, NWConnection, CFNetwork all honor these settings
 * without any app-side changes.
 *
 * SCDynamicStore APIs are marked API_UNAVAILABLE(ios) in SDK headers,
 * but the functions exist in the simulator runtime (which is macOS code).
 * We use dlsym to load them at runtime.
 *
 * Usage:
 *   handleProxyAction(@"set", @[@"127.0.0.1", @"8080"])         // HTTP proxy
 *   handleProxyAction(@"set", @[@"127.0.0.1", @"1080", @"socks"]) // SOCKS proxy
 *   handleProxyAction(@"clear", @[])                            // Clear proxy
 *
 * @param action "set" or "clear"
 * @param arguments For "set": [host, port, type?]. For "clear": empty.
 * @return 0 on success, 1 on failure
 */
int handleProxyAction(NSString *action, NSArray<NSString *> *arguments);

/**
 * Builds an NSDictionary containing HTTP/HTTPS proxy configuration.
 * The returned dictionary is suitable for SCDynamicStoreSetValue
 * (toll-free bridged via __bridge).
 *
 * @param host The proxy hostname or IP address
 * @param port The proxy port number
 * @return An NSDictionary with HTTP and HTTPS proxy keys
 */
NSDictionary<NSString *, id> *buildHTTPProxyDict(NSString *host, int port);

/**
 * Builds an NSDictionary containing SOCKS proxy configuration.
 * The returned dictionary is suitable for SCDynamicStoreSetValue
 * (toll-free bridged via __bridge).
 *
 * @param host The proxy hostname or IP address
 * @param port The proxy port number
 * @return An NSDictionary with SOCKS proxy keys
 */
NSDictionary<NSString *, id> *buildSOCKSProxyDict(NSString *host, int port);

/**
 * Builds an NSDictionary with no proxy configuration (clears all proxy settings).
 * The returned dictionary contains only FTPPassive=1.
 *
 * @return An NSDictionary with cleared proxy settings
 */
NSDictionary<NSString *, id> *buildEmptyProxyDict(void);

NS_ASSUME_NONNULL_END
