/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreFoundation/CoreFoundation.h>

/** TCC.framework inputs are **borrowed** for the synchronous call; no input ownership transfers. */
typedef Boolean (*FBTCCAccessSetForBundleIdWithOptions)(CFStringRef service, CFStringRef bundleID, Boolean allowed, CFDictionaryRef options);
/** Resets to not-determined. Inputs are **borrowed** for the synchronous call. */
typedef Boolean (*FBTCCAccessResetForBundleIdWithOptions)(CFStringRef service, CFStringRef bundleID, CFDictionaryRef options);
/** kTCCSetNoKill exports a CFStringRef variable. Its value is **borrowed** for the framework's lifetime. */
typedef const CFStringRef *FBTCCNoKillSymbol;
