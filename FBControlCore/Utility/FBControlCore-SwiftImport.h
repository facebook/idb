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

#import <FBControlCore/FBArchiveOperations.h>
#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBCrashLog.h>
#import <FBControlCore/FBEventReporterSubject.h>
#import <FBControlCore/FBFileReader.h>
#import <FBControlCore/FBInstalledApplication.h>
#import <FBControlCore/FBInstrumentsOperation.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBProcessSpawnConfiguration.h>
#import <FBControlCore/FBProcessTerminationStrategy.h>
#import <FBControlCore/FBVideoStreamConfiguration.h>
#import <FBControlCore/FBXCTraceRecordCommands.h>
#import <FBControlCore/FBiOSTargetConfiguration.h>

// Pre-define SWIFT_CLASS macros without objc_subclassing_restricted
// to allow ObjC subclassing of open Swift classes (e.g. FBControlCoreError).
// The -Swift.h header guards these with #if !defined(SWIFT_CLASS).
#if !defined(SWIFT_CLASS)
 # define SWIFT_CLASS_EXTRA
 # define SWIFT_CLASS(SWIFT_NAME) SWIFT_RUNTIME_NAME(SWIFT_NAME) SWIFT_CLASS_EXTRA
 # define SWIFT_CLASS_NAMED(SWIFT_NAME) SWIFT_COMPILE_NAME(SWIFT_NAME) SWIFT_CLASS_EXTRA
#endif

#if __has_include(<FBControlCore/FBControlCore-Swift.h>)
 #import <FBControlCore/FBControlCore-Swift.h>
#endif
