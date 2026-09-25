/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for CoreFoundation's keyed-archive UID type.
//
// A keyed archive stores every cross-reference as a CFKeyedArchiverUID holding an
// index into the archive's `$objects` array. `NSKeyedUnarchiver` resolves those for
// you, but only by instantiating each archived class -- which is no use for an
// archive written by another process, whose classes (BulletinBoard's, here) do not
// exist in this one. Reading the archive as a plain property list and resolving the
// references by hand avoids that, and needs these two to recognise a reference and
// read its index.
//
// Both are private CoreFoundation symbols, so they are resolved with
// dlsym(RTLD_DEFAULT, ...) and typed by the function pointers below rather than declared
// `extern`: an `extern` declaration leaves an undefined symbol in the guest's Mach-O, and
// a runtime that does not export it then fails the whole binary at launch instead of
// failing this one read.
//
// A reference is an opaque CFType, held as const void * so nothing here links the CF type.
// Neither entry point transfers ownership: the returned value is a scalar, and the
// reference itself stays owned by the property list it came from.

#import <CoreFoundation/CoreFoundation.h>

/** _CFKeyedArchiverUIDGetTypeID() — the type id of a reference, for comparing against `CFGetTypeID`. */
typedef CFTypeID (*FBKeyedArchiverUIDGetTypeIDFn)(void);

/** _CFKeyedArchiverUIDGetValue(uid) — the `$objects` index a reference points at. */
typedef uint32_t (*FBKeyedArchiverUIDGetValueFn)(const void *uid);
