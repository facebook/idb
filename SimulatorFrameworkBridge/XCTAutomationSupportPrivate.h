/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the XCTAutomationSupport private API.
//
// XCTAutomationSupport ships in the simulator runtime's Developer root rather than in the SDK, so it is
// dlopen-loaded and its classes are resolved with objc_lookUpClass. Nothing here is referenced at link
// time; the declarations exist so the messages sent to those classes are checked by the compiler rather
// than hand-cast through objc_msgSend.

#import <Foundation/Foundation.h>

#import "AXRuntimePrivate.h"

NS_ASSUME_NONNULL_BEGIN

/** The framework's path inside the booted runtime root, for dlopen. */
#define FBAXPathXCTAutomationSupport \
        "/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework/XCTAutomationSupport"

/**
 * The key `-[XCTAccessibilityFramework attributesForElement:attributes:error:]` reports the underlying
 * FBAXError under, on the NSError it returns. It is a read's only window onto the AX runtime's own
 * error, and so the only way to tell an unreadable application apart from a read that went wrong.
 */
#define FBAXAccessibilityErrorKey @"accessibility-error"

/**
 * XCTDefaultSnapshotParameters() — the option dictionary a snapshot must start from.
 *
 * `userTestingSnapshotForElement:options:error:` hands its options to the accessibility server verbatim.
 * A dictionary not built from these defaults makes the server answer NULL under kAXErrorSuccess, which is
 * indistinguishable from any other mistake, so this is not an optional convenience.
 */
typedef NSDictionary<NSString *, id> *_Nullable (*FBAXDefaultSnapshotParametersFn)(void);

/**
 * XCAXAccessibilityAttributesForStringAttributes(names) — converts `XC_kAXXCAttribute*` names into the
 * numbers a snapshot's `attributes` option takes, positionally.
 *
 * The numbers are the runtime's own and nothing promises they are stable across versions, so a snapshot's
 * numeric keys are mapped back through the result of this call rather than through any hardcoded table.
 */
typedef NSArray<NSNumber *> *_Nullable (*FBAXAttributeNumbersForNamesFn)(NSArray<NSString *> *names);

/**
 * The accessibility client XCTest drives a device's AX server through.
 */
@interface XCTAccessibilityFramework : NSObject

/**
 * Registers the remote-access client context the AX server answers to. Together with the dlopens this
 * is the dominant setup cost of a read (~260 ms), so an instance is created once and reused.
 */
- (instancetype)initForRemoteAccess;

/**
 * Reads `attributes` off `element` in one mach round trip, returning them keyed by attribute name.
 *
 * Returns nil on failure with `*error` set, carrying the runtime's own FBAXError under
 * FBAXAccessibilityErrorKey.
 */
- (nullable NSDictionary<NSString *, id> *)attributesForElement:(id)element
                                                     attributes:(NSArray<NSString *> *)attributes
                                                          error:(NSError **)error;

/**
 * Reads a whole bounded subtree in **one** round trip — the call XCUITest walks hierarchies with.
 *
 * Its body is a single `AXUIElementCopyParameterizedAttributeValue` for attribute `0x1731e`, with
 * `options` handed to the accessibility server verbatim; the method itself reads only
 * `options[@"attributes"]`, and only to log it. So the contract is the server's, not this framework's.
 *
 * Recognised option keys, from the framework binary: `maxDepth`, `maxChildren`, `maxArrayCount`,
 * `snapshotAttributes`, `attributes`, `snapshotKeyHonorModalViews`, `traverseFromParentsToChildren`,
 * `maximumCompression`. XCTest sanitises them in `XCTest.framework` before calling, which this guest
 * does not have, so a malformed dictionary reaches the server unfiltered.
 *
 * **Not equivalent to N calls to `attributesForElement:`.** This one sets the AX requesting client (that
 * method does not), so client-sensitive attributes can answer differently.
 */
- (nullable id)userTestingSnapshotForElement:(id)element
                                     options:(NSDictionary<NSString *, id> *)options
                                       error:(NSError **)error;

@end

/**
 * The element handle the attribute reader takes, and the bridge to and from the raw AXRuntime
 * AXUIElementRef.
 *
 * No class method here validates the process it names: a nonexistent pid, a live non-application
 * process and pid 0 all vend an element. Whether a pid names something readable is knowable only from
 * the FBAXError a read of that element reports.
 */
@interface XCAccessibilityElement : NSObject

/** The application element for a process. Non-nil for any pid, readable or not. */
+ (nullable instancetype)elementWithProcessIdentifier:(pid_t)pid;

/**
 * Re-wraps a raw AXUIElementRef — a hit-test result — so the attribute reader can read it.
 *
 * **Retains** `axUIElement`: the caller keeps its own reference and releases it as it normally would.
 */
+ (nullable instancetype)elementWithAXUIElement:(void *)axUIElement;

/**
 * The raw AXUIElementRef underneath, for a point hit-test.
 *
 * **Borrows**: the ref is owned by the element and dies with it, and ARC is free to release the element
 * at its last use. A caller that outlives that use must retain the ref itself.
 */
- (void *_Nullable)AXUIElement;

@end

/**
 * The class-side interface, for messaging a class resolved with `objc_lookUpClass`.
 *
 * A `Class` carries no type, so a send to one is resolved against whatever declaration in the translation
 * unit happens to share the selector — which is the wrong class's declaration as easily as the right one.
 * Casting the looked-up class to `Class<XCAccessibilityElementClass>` names the declaration to check
 * against.
 */
@protocol XCAccessibilityElementClass <NSObject>
+ (nullable XCAccessibilityElement *)elementWithProcessIdentifier:(pid_t)pid;
+ (nullable XCAccessibilityElement *)elementWithAXUIElement:(void *)axUIElement;
@end

NS_ASSUME_NONNULL_END
