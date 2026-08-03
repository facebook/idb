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
 * Reads only (element writes are served by the existing HID / testmanagerd / ax backends).
 *
 * Verbs (over the same core):
 *   - describe --pid <pid> [--max-depth <n>] [--max-nodes <n>]
 *                                              reads the whole element tree. The caller's bounds are
 *                                              honoured when given, so a host driving several reader
 *                                              backends gets the same truncation point from each.
 *   - hittest  --pid <pid> --x <x> --y <y>     reads just the element at a point, via a single
 *                                              AXUIElementCopyElementAtPosition round-trip (no walk).
 *   - frontmost --x <x> --y <y>                resolves the frontmost application's pid via a system-wide
 *                                              hit-test at the caller's screen anchor (the screen
 *                                              centre) — no host-side CoreSimulator round-trip. The
 *                                              simulator's AX server does not report AXFocusedApplication,
 *                                              so focus is resolved positionally.
 * Front-ends:
 *   - oneshot:    accessibility <verb> ...       (runs once, prints JSON, exits)
 *   - persistent: accessibility serve <socket>   (serves many requests over a UDS)
 *
 * The persistent `serve` mode binds a Unix-domain socket and answers length-prefixed JSON request
 * frames (4-byte big-endian length + a request object, same envelope as oneshot) with the framework
 * cached once, so a host client reusing one warm process reads ~30x faster than re-spawning per read.
 *
 * @param action The verb ("describe", "hittest", or "frontmost") or the "serve" action.
 * @param arguments Remaining argv (e.g. @[@"--pid", @"1234"], @[@"--pid", @"1234", @"--x", @"20", @"--y", @"40"], @[@"--x", @"201", @"--y", @"437"] for frontmost, or @[socketPath]).
 * @return 0 on success, 1 on failure.
 */
int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments);

/**
 * The transport-agnostic request handler shared by the oneshot argv front-end and any future socket
 * server. Request keys: "verb" (@"describe", @"hittest", or @"frontmost"), "pid" (NSNumber, describe /
 * hittest), optional "maxDepth" and "maxNodes" (NSNumber, describe — the caller's read bounds), "x"/"y"
 * (NSNumber, hittest and frontmost — the point / screen anchor). Response is @{@"ok": @YES, @"tree": <node>} on success; @{@"ok": @YES, @"empty":
 * @YES} when a hittest finds no element at the point (a valid empty result, distinct from a failure);
 * @{@"ok": @YES, @"pid": <NSNumber>, @"method": <string>} for frontmost; or @{@"ok": @NO, @"error":
 * <string>} on failure. Each node is keyed by the `XC_kAXXC*` attributes with a JSON-safe frame (a
 * CGRect dictionary representation) and its children recursed in place.
 */
NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request);

/**
 * Serializes a response dictionary to the JSON bytes both front-ends emit.
 *
 * JSON cannot represent infinity or NaN, and `NSJSONSerialization` *raises* on a non-finite number
 * rather than returning an error — which would abort this process mid-read. An off-screen or
 * still-laying-out element reports a non-finite frame coordinate, so every number is sanitized to
 * null first (matching the host serializer) and the serialization is guarded, degrading to an error
 * frame the client can read rather than terminating the reader.
 */
NSData *FBAXBridgeSerializeResponse(NSDictionary<NSString *, id> *response);

NS_ASSUME_NONNULL_END
