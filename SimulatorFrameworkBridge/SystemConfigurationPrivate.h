/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for SystemConfiguration private API.
//
// SCDynamicStore is a Core Foundation API for reading and writing
// system configuration keys in configd (or configd_sim inside the
// simulator). Network proxy settings live at the key returned by
// SCDynamicStoreKeyCreateProxies ("State:/Network/Global/Proxies").
//
// The iOS SDK headers mark these functions API_UNAVAILABLE(ios), but
// they exist in the simulator runtime because the simulator is macOS
// code. We define typed function pointers here and resolve them at
// runtime via dlsym.

#import <CoreFoundation/CoreFoundation.h>

/**
 * Opaque reference to an SCDynamicStore session. In the real SDK this
 * is SCDynamicStoreRef (a CFTypeRef), but since the header is
 * unavailable we define our own compatible type.
 */
typedef void *SCDynStoreRef;

/**
 * Creates a new session with the dynamic store (configd_sim).
 * Parameters: allocator, name (for logging), callback (unused), context (unused).
 * Returns an SCDynStoreRef that must be released with CFRelease.
 */
typedef SCDynStoreRef (*SCDynamicStoreCreate_fn)(CFAllocatorRef, CFStringRef, void *, void *);

/**
 * Sets a value for a key in the dynamic store. Used to write proxy
 * configuration dictionaries to the proxies key.
 * Returns true on success.
 */
typedef Boolean (*SCDynamicStoreSetValue_fn)(SCDynStoreRef, CFStringRef, CFPropertyListRef);

/**
 * Copies the current value for a key from the dynamic store.
 * Caller must CFRelease the returned value.
 */
typedef CFPropertyListRef (*SCDynamicStoreCopyValue_fn)(SCDynStoreRef, CFStringRef);

/**
 * Creates the well-known key for proxy configuration:
 * "State:/Network/Global/Proxies". Caller must CFRelease the result.
 */
typedef CFStringRef (*SCDynamicStoreKeyCreateProxies_fn)(CFAllocatorRef);

/**
 * Posts a notification that the value for a key has changed, causing
 * observers (e.g., NSURLSession, CFNetwork) to re-read proxy settings.
 * Optional — not all simulator runtimes export this symbol.
 */
typedef Boolean (*SCDynamicStoreNotifyValue_fn)(SCDynStoreRef, CFStringRef);
