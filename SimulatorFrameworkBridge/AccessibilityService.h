/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The `accessibility` service: a bundle-free, XCUI-grade accessibility reader that runs inside the
 * simulator as a first-class accessibility *client* — the same role testmanagerd plays — with no
 * daemon, no DTX channel, and no `.xctest` bundle.
 *
 * It instantiates `XCTAccessibilityFramework` in remote-access mode (which registers the remote-access
 * client context the app's in-process AX server requires) and reads an app's element tree by pid via
 * the AXRuntime C API (mach -> the app's AX server). The tree is emitted as JSON keyed by the
 * `XC_kAXXC*` attributes — the same node shape the testmanagerd read path produces, so the host can
 * feed it through the shared accessibility serializer unchanged.
 *
 * The AX read logic is transport-agnostic: `FBAXBridgeHandleRequest` takes a request dictionary and
 * returns a response dictionary, so a future socket "serve" front-end can reuse it verbatim. The
 * oneshot front-end `handleAccessibilityAction` parses argv, calls the core, and prints the response
 * as JSON on stdout.
 *
 * Reads only for now; writes (tap/scroll/set-value via in-guest HID) are added in a later commit.
 *
 * Usage (oneshot):
 *   accessibility describe --pid <pid> [--max-depth <n>]
 *
 * @param action The action to perform ("describe").
 * @param arguments Remaining argv beyond service and action (e.g. @[@"--pid", @"1234"]).
 * @return 0 on success, 1 on failure.
 */
int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments);

/**
 * The transport-agnostic request handler shared by the oneshot argv front-end and any future socket
 * server. Request keys: "verb" (currently @"describe"), "pid" (NSNumber), optional "maxDepth"
 * (NSNumber). Response is either @{@"ok": @YES, @"tree": <node>} or @{@"ok": @NO, @"error": <string>}.
 * Each node is keyed by the `XC_kAXXC*` attributes with a JSON-safe frame (a CGRect dictionary
 * representation) and its children recursed in place.
 */
NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request);

NS_ASSUME_NONNULL_END
