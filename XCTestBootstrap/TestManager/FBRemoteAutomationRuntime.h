/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBRemoteAutomationProtocols.h"

@class DTXConnection;
@class DTXProxyChannel;

NS_ASSUME_NONNULL_BEGIN

/**
 Constructs the runtime-loaded DTX and XCTest objects for the remote-automation session and casts
 the DTX proxy to its typed interface.

 Every class this reaches is vended by Apple frameworks loaded at runtime and relocated per Xcode,
 so each is looked up by name and never `alloc`d directly. `DTXConnectionServices` is linked, so the
 DTX types appear in the typed signatures below. The `XCTest` payload classes are not linked — they
 are `dlopen`d at runtime — so they are returned as `id`: naming them in a Swift-consumed signature
 would emit an `_OBJC_CLASS_$_` reference that is undefined at link. Each factory returns nil with
 `error` set when its class is unavailable, so the Swift caller surfaces the failure as a thrown
 error.
 */
@interface FBRemoteAutomationRuntime : NSObject

/**
 Wraps an already-connected AF_UNIX socket in a DTX transport and connection, taking ownership of
 `socketHandle`.

 @param socketHandle a connected AF_UNIX socket file descriptor.
 @param transportDisconnect invoked when the DTX transport reports a socket disconnect.
 @param connectionDisconnect invoked when the DTX connection reports a disconnect.
 @param error set (and the socket closed) if the DTX classes are unavailable.
 @return the connection, or nil on failure.
 */
+ (nullable DTXConnection *)connectionForSocketHandle:(int)socketHandle
                                  transportDisconnect:(void (^)(void))transportDisconnect
                                 connectionDisconnect:(void (^)(void))connectionDisconnect
                                                error:(NSError **)error;

/**
 Makes a proxy channel over `connection` for the remote-automation interfaces, installs the one-shot
 return-value allow-list, and sets `exportedObject` on `queue`. The allow-list must be installed
 before the connection is resumed, so it is bundled into channel construction here. Returns the
 channel, or nil with `error` set on failure.
 */
+ (nullable DTXProxyChannel *)proxyChannelForConnection:(DTXConnection *)connection
                                         exportedObject:(id)exportedObject
                                                  queue:(dispatch_queue_t)queue
                                                  error:(NSError **)error;

/**
 The typed remote proxy vended by `proxyChannel`. The DTX forwarding proxy responds to the
 `FBRemoteAutomationServer` selectors but does not declare conformance, so it is cast here where the
 concrete channel type is in scope.
 */
+ (id<XCTDRemoteAutomationServer>)remoteProxyForChannel:(DTXProxyChannel *)proxyChannel;

/**
 A pointer event path (`XCPointerEventPath`) beginning at a touch point, or nil with `error` set if
 the class is unavailable.
 */
+ (nullable id)pointerEventPathForTouchAtX:(double)x y:(double)y error:(NSError **)error
  NS_SWIFT_NAME(pointerEventPath(forTouchAtX:y:));

/**
 An `XCSynthesizedEventRecord` composed of the given `XCPointerEventPath` objects, or nil with
 `error` set if the class is unavailable.
 */
+ (nullable id)synthesizedEventRecordWithName:(NSString *)name
                                 pointerPaths:(NSArray<id> *)pointerPaths
                                        error:(NSError **)error;

/**
 The application accessibility root (`XCAccessibilityElement`) for a process, or nil with `error` set
 if the class is unavailable.
 */
+ (nullable id)applicationElementForProcessIdentifier:(int)processIdentifier error:(NSError **)error;

/**
 An `XCDeviceEvent` for a hardware button press: a HID `page`/`usage` held for `duration` seconds, or
 nil with `error` set if the class is unavailable. Submitted via `_XCTD_performDeviceEvent:`.
 */
+ (nullable id)deviceEventWithPage:(unsigned int)page
                             usage:(unsigned int)usage
                          duration:(double)duration
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
