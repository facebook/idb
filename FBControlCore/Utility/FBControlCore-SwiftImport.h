/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// This header imports all ObjC types referenced by Swift code,
// then imports FBControlCore-Swift.h. Stub headers for converted
// classes should import this file so that ObjC consumers get the
// Swift class declarations with all required types defined first.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBCrashLog.h>
#import <FBControlCore/FBEventReporterSubject.h>
#import <FBControlCore/FBInstalledApplication.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBVideoStreamConfiguration.h>
#import <FBControlCore/FBXCTraceRecordCommands.h>

#if __has_include(<FBControlCore/FBControlCore-Swift.h>)
 #import <FBControlCore/FBControlCore-Swift.h>
#endif
