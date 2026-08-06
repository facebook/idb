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
