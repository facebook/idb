/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for SystemConfiguration's SCDynamicStore API. The iOS SDK marks these functions
// API_UNAVAILABLE(ios), but configd_sim exports them in the simulator runtime; they are resolved with
// dlsym and typed by the function pointers below.

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
 * Sets a value for a key in the dynamic store. Returns true on success.
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
