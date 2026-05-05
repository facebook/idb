/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
