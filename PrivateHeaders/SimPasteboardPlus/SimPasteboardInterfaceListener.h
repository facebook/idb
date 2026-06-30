/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The in-simulator server end of the pasteboard connection (Xcode 26.6+, SimPasteboardPlus).

 We do not run a listener — that lives inside the booted device. Only its `machServiceName` class
 property is needed host-side: it names the Mach service to resolve via `-[SimDevice lookup:error:]`
 before connecting a SimPasteboardInterface. As with SimPasteboardInterface, the clean name is
 mapped to the Swift-mangled runtime name and the class is weak-linked.
 */
__attribute__((objc_runtime_name("_TtC17SimPasteboardPlus30SimPasteboardInterfaceListener")))
@interface SimPasteboardInterfaceListener : NSObject

@property (class, readonly) NSString *machServiceName;

@end

NS_ASSUME_NONNULL_END
