/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Runs an accessibility command inside the simulator.
 *
 * `describe`, `hittest`, `perform`, and `setvalue` execute one request and print its JSON
 * response. `serve` accepts length-prefixed JSON requests on a Unix-domain socket and reuses the
 * initialized accessibility runtime. Arguments after the action are parsed as flag/value pairs.
 *
 * @return 0 on success, 1 on failure.
 */
int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments);

/**
 * Handles one decoded axbridge request. Both the argv adapter and socket server use this dispatcher.
 * Responses use the shared `{ok, tree | empty | error}` envelope and include structured metadata when
 * applicable.
 */
NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request);

/**
 * Serializes a response after replacing non-finite numbers with `null`. Serialization failures become
 * error envelopes so malformed element values cannot terminate the guest.
 */
NSData *FBAXBridgeSerializeResponse(NSDictionary<NSString *, id> *response);

NS_ASSUME_NONNULL_END
