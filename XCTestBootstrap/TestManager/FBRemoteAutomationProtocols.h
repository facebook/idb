/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The receipt returned by every remote-automation invocation. The guest daemon delivers each
 result asynchronously; `handleCompletion:` fires exactly once with the return value or an
 error. Backed at runtime by `DTXRemoteInvocationReceipt`, whose `handleCompletion:` this
 declares — the concrete class is never named in Swift, only messaged through this protocol.
 */
@protocol FBRemoteAutomationReceipt <NSObject>

// The daemon hands the value over and keeps no reference to it, so Swift can treat it as
// transferred rather than shared. Without this the value imports as task-isolated and cannot be
// passed to a continuation without an unsafe opt-out.
- (void)handleCompletion:(void (^)(id _Nullable NS_SWIFT_SENDING value, NSError *_Nullable error))completion;

@end

/**
 The local (client-side) interface the daemon may call back on. The remote-automation channel never
 calls back, so this is empty; it exists only to satisfy the DTX proxy's exported interface, and the
 exported object must conform to it.

 Named to match the guest daemon's interface: `xct_makeProxyChannelWithRemoteInterface:` derives the
 DTX channel identifier from the interface protocol names, so the channel only routes when both sides
 carry the daemon's real names. It is still declared in-module (not imported from the private XCTest
 umbrella).
 */
@protocol XCTDRemoteAutomationClient <NSObject>

@end

/**
 The remote interface vended by the guest `testmanagerd` over its unauthenticated, session-less
 remote-automation DTX channel.

 Named to match the daemon's interface (see `XCTDRemoteAutomationClient`) so the channel routes,
 but declared in-module — rather than imported from the private XCTest umbrella — so the Swift half
 of `XCTestBootstrap` messages the typed proxy directly with no external framework import. The DTX
 proxy forwards by selector at runtime, so the host-side declaration only needs matching selectors
 and object argument types. Every selector returns a receipt; the object arguments are the wire
 payloads (`NSNumber`, `NSDictionary`, `XCSynthesizedEventRecord`, `XCAccessibilityElement`).
 */
@protocol XCTDRemoteAutomationServer <NSObject>

- (nullable id<FBRemoteAutomationReceipt>)_XCTD_beginSessionWithClientProtocolVersion:(id)version
  NS_SWIFT_NAME(beginSession(clientProtocolVersion:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_exchangeCapabilities:(id)capabilities
  NS_SWIFT_NAME(exchangeCapabilities(_:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_loadAccessibilityWithTimeout:(id)timeout
  NS_SWIFT_NAME(loadAccessibility(timeout:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_requestElementAtPoint:(id)point
  NS_SWIFT_NAME(requestElement(atPoint:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_fetchAttributes:(id)attributes forElement:(id)element
  NS_SWIFT_NAME(fetchAttributes(_:forElement:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_synthesizeEvent:(id)event implicitConfirmationInterval:(id)interval
  NS_SWIFT_NAME(synthesizeEvent(_:implicitConfirmationInterval:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_setAttribute:(id)attribute value:(id)value element:(id)element
  NS_SWIFT_NAME(setAttribute(_:value:element:));
- (nullable id<FBRemoteAutomationReceipt>)_XCTD_performDeviceEvent:(id)event
  NS_SWIFT_NAME(performDeviceEvent(_:));

@end

NS_ASSUME_NONNULL_END
