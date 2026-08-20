/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the AXRuntime private API.
//
// AXRuntime holds the accessibility C ABI: the AXUIElement entry points and the error codes they
// return. No SDK header available to an iphonesimulator target declares any of it, and the framework is
// dlopen-loaded from the booted runtime root rather than linked, so the entry points are resolved with
// dlsym(RTLD_DEFAULT, ...) and typed by the function pointers below.
//
// An AXUIElementRef is an opaque CFType, held as void * throughout so nothing here links the AX C types.
// The ownership each entry point transfers is stated at its declaration rather than at the call site,
// because getting it wrong is a use-after-free, not a compile error.

#import <Foundation/Foundation.h>

/** The framework's path inside the booted runtime root, for dlopen. */
#define FBAXPathAXRuntime "/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime"

/**
 * The AX runtime's C ABI error codes, as observed on a booted simulator runtime — no SDK header
 * available to the guest declares them. Named as an enum so that a result is compared against the
 * outcome it means rather than against a bare integer.
 *
 * Only the codes the reader distinguishes are listed; any other code is a failure with no further
 * meaning attached to it.
 */
typedef NS_ENUM(int32_t, FBAXError) {
  /** kAXErrorSuccess. */
  FBAXErrorSuccess = 0,
  /** kAXErrorInvalidUIElement: the point is genuinely empty — a valid empty result, not a failure. */
  FBAXErrorInvalidUIElement = -25202,
  /** kAXErrorServerNotFound: nothing answered — a dead pid, or a process that is not an application. */
  FBAXErrorServerNotFound = -25215,
  /** kAXErrorIPCTimeout: a live application that is not answering (e.g. SIGSTOPped). */
  FBAXErrorIPCTimeout = -25216,
};

/**
 * The AX runtime's identifiers for the semantic actions an element can perform, as observed in the
 * translation table AccessibilityPlatformTranslation maps its own AXPAction constants through — no SDK
 * header available to the guest declares them.
 *
 * On iOS an action is a 32-bit integer rather than the CFString macOS uses. Actions and attributes are
 * separate namespaces whose numbers overlap: `FBAXActionIdentifierScrollDownByPage` and
 * `FBAXAttributeIdentifierValue` are both 0x7d6 and have nothing to do with each other, so the two are
 * named apart here to stop one being passed where the other belongs.
 *
 * Only the actions the writer performs are listed.
 */
typedef NS_ENUM(uint32_t, FBAXActionIdentifier) {
  /** AXPActionScrollToVisible: bring the element into its scroll container's viewport. */
  FBAXActionIdentifierScrollToVisible = 0x7d3,
  /** AXPActionScrollDownByPage. */
  FBAXActionIdentifierScrollDownByPage = 0x7d6,
  /** AXPActionScrollUpByPage. */
  FBAXActionIdentifierScrollUpByPage = 0x7d7,
  /** AXPActionScrollLeftByPage. */
  FBAXActionIdentifierScrollLeftByPage = 0x7d8,
  /** AXPActionScrollRightByPage. */
  FBAXActionIdentifierScrollRightByPage = 0x7d9,
  /** AXPActionPress: activate the element, the semantic equivalent of a tap on it. */
  FBAXActionIdentifierPress = 0x7da,
};

/**
 * The AX runtime's identifiers for the attributes an element exposes, as observed in the lookup table
 * `AXAttributeForXCAttribute` translates through.
 *
 * A read never needs these: XCTAutomationSupport takes attribute *names* ("XC_kAXXCAttributeValue") and
 * does the translation itself. A write goes straight to the C ABI below, which takes the number.
 *
 * See `FBAXActionIdentifier` for why the two namespaces are kept apart.
 */
typedef NS_ENUM(uint32_t, FBAXAttributeIdentifier) {
  /** kAXXCAttributeValue: the element's value — what a set-value writes. */
  FBAXAttributeIdentifierValue = 0x7d6,
};

/**
 * The geometry types an `AXValue` wraps, as the runtime numbers them — no SDK header available to the
 * guest declares them. The numbers come from the type name the runtime prints in an AXValue's
 * description. Only the types the reader unwraps are listed.
 */
typedef NS_ENUM(uint32_t, FBAXValueType) {
  /** kAXValueCGPointType. */
  FBAXValueTypeCGPoint = 1,
  /** kAXValueCGRectType. */
  FBAXValueTypeCGRect = 3,
};

/**
 * AXValueGetType(value) — the `FBAXValueType` an AXValue wraps, for anything that is one.
 *
 * **Borrows** the value and transfers no ownership. Held as const void * for the same reason an element
 * is held as void *.
 */
typedef uint32_t (*FBAXValueGetTypeFn)(const void *value);

/**
 * AXValueGetValue(value, type, out) — unwraps an AXValue into `out`, which must point at storage for
 * `type`. Answers false and leaves `out` untouched when the value does not hold that type.
 *
 * The type is not inferred from `out`, so a rect read out of a point-typed value is a silent wrong
 * answer rather than a failure — check `AXValueGetType` first.
 *
 * **Borrows** the value and transfers no ownership.
 */
typedef Boolean (*FBAXValueGetValueFn)(const void *value, uint32_t type, void *out);

/**
 * AXUIElementCopyElementAtPosition(application, x, y, &element) — a single-round-trip hit-test
 * returning just the element at a point. x and y are 32-bit floats.
 *
 * On FBAXErrorSuccess the out-parameter is **+1 retained** and owned by the caller.
 */
typedef int32_t (*FBAXCopyElementAtPositionFn)(void *application, float x, float y, void **element);

/**
 * AXUIElementCreateSystemWide() — the system-wide element, the seed for a display-wide (rather than
 * pid-scoped) hit-test. Returns a **+1 retained** element owned by the caller.
 *
 * AXFocusedApplication on that element is deliberately not used: the simulator's AX server reports it as
 * kAXErrorNoValue (unlike macOS), so focus is resolved positionally instead.
 */
typedef void *(*FBAXCreateSystemWideFn)(void);

/**
 * AXUIElementGetPid(element, &pid) — the element's owning process. **Borrows** the element and
 * transfers no ownership.
 */
typedef int32_t (*FBAXGetPidFn)(void *element, pid_t *pid);

/**
 * AXUIElementPerformAction(element, action) — performs one semantic action on an element, in a single
 * round trip to the owning application's accessibility server. `action` is an `FBAXActionIdentifier`.
 *
 * **Borrows** the element and transfers no ownership.
 */
typedef int32_t (*FBAXPerformActionFn)(void *element, uint32_t action);

/**
 * AXUIElementSetAttributeValue(element, attribute, value) — writes one attribute on an element, in a single
 * round trip. `attribute` is an `FBAXAttributeIdentifier`; `value` is a CFTypeRef, held as const void * for
 * the same reason an element is held as void *.
 *
 * **Borrows** both the element and the value, and transfers no ownership of either — the caller still owns
 * the value after the call returns.
 */
typedef int32_t (*FBAXSetAttributeValueFn)(void *element, uint32_t attribute, const void *value);
