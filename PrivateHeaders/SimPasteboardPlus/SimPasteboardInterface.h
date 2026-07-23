/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import <SimPasteboardPlus/SimPasteboardDelegate.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A connection that syncs a host-owned NSPasteboard to/from a booted device's pasteboard.

 This is the modern (Xcode 26.6+) replacement for the in-process SimDevicePasteboard API, which
 Apple removed. It is a Swift @objc class in the private SimPasteboardPlus.framework, with no ObjC
 rename, so its runtime name is the Swift-mangled symbol — mapped back to this clean name via
 `objc_runtime_name`. The class is weak-linked (see SimPasteboardPlus.tbd); on older CoreSimulator
 it is absent, which `FBSimPasteboardInterfaceIsAvailable()` reports.

 There is no one-shot get/set: the caller owns an NSPasteboard, hands it to `managingPasteboard:`,
 then `-push` (host -> device) or `-pull` (device -> host) syncs it. Construct it the way
 Simulator.app's DeviceCoordinator does: resolve the port via
 `-[SimDevice lookup:[SimPasteboardInterfaceListener machServiceName] error:]`, then init.
 Only the subset used for a one-shot copy/paste is declared.
 */
__attribute__((objc_runtime_name("_TtC17SimPasteboardPlus22SimPasteboardInterface")))
@interface SimPasteboardInterface : NSObject

- (instancetype)initWithConnectingToPort:(unsigned int)port
                      managingPasteboard:(NSPasteboard *)pasteboard
                                delegate:(nullable id<SimPasteboardDelegate>)delegate
                           delegateQueue:(nullable dispatch_queue_t)delegateQueue;

/// Sends the managed pasteboard's current contents to the connected device.
- (void)push;
/// Requests the connected device's pasteboard contents into the managed pasteboard.
- (void)pull;
- (void)enableRemoteAutosync;
- (void)disableRemoteAutosync;

@end

/**
 YES when the weak-linked SimPasteboardPlus pasteboard API (Xcode 26.6+) is present at runtime.

 This must be Objective-C: it references the real, weak-linked class symbol, so a rename, removal,
 or unlink fails the build (unlike `NSClassFromString`); and `[SimPasteboardInterface class]`
 null-checks the weak class (an absent weak class resolves to nil and `objc_msgSend(nil)` returns
 nil), which Swift cannot do — referencing an absent weak class from Swift traps instead.
 */
NS_INLINE BOOL FBSimPasteboardInterfaceIsAvailable(void) {
  return [SimPasteboardInterface class] != Nil;
}

NS_ASSUME_NONNULL_END
