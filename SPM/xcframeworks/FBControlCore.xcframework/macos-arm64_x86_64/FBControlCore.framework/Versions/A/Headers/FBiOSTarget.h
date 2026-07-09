/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBInstrumentsCommands.h>
#import <FBControlCore/FBScreenshotCommands.h>
#import <FBControlCore/FBiOSTargetConstants.h>

@class FBDeviceType;
@class FBOSVersion;
@class FBProcessInfo;
@class FBTemporaryDirectory;
@class FBiOSTargetDiagnostics;
@class FBiOSTargetScreenInfo;
@protocol FBControlCoreLogger;

@protocol FBiOSTargetInfo;
@protocol FBiOSTarget;

/**
 The canonical string representation of the state enum.
 */
FOUNDATION_EXTERN FBiOSTargetStateString _Nonnull FBiOSTargetStateStringFromState(FBiOSTargetState state);

/**
 The canonical enum representation of the state string.
 */
FOUNDATION_EXTERN FBiOSTargetState FBiOSTargetStateFromStateString(FBiOSTargetStateString _Nonnull stateString);

/**
 The canonical string representations of the FBiOSTargetType Enum.
 */
FOUNDATION_EXTERN NSString *_Nonnull FBiOSTargetTypeStringFromTargetType(FBiOSTargetType targetType);

/**
 A Default Comparison Function that can be called for different implementations of FBiOSTarget.
 */
FOUNDATION_EXTERN NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> _Nonnull left, id<FBiOSTarget> _Nonnull right);

/**
 Constructs a string description of the provided target.
 */
FOUNDATION_EXTERN NSString *_Nonnull FBiOSTargetDescribe(id<FBiOSTargetInfo> _Nonnull target);

/**
 Constructs an NSPredicate matching the specified UDID.
 */
FOUNDATION_EXTERN NSPredicate *_Nonnull FBiOSTargetPredicateForUDID(NSString * _Nonnull udid);

/**
 Constructs an NSPredicate matching the specified UDIDs.
 */
FOUNDATION_EXTERN NSPredicate *_Nonnull FBiOSTargetPredicateForUDIDs(NSArray<NSString *> * _Nonnull udids);

/**
 Constructs a future that resolves when the target resolves to a provided state.
 */
FOUNDATION_EXTERN FBFuture<NSNull *> *_Nonnull FBiOSTargetResolveState(id<FBiOSTarget> _Nonnull target, FBiOSTargetState state);

/**
 Constructs a future that resolves when the target leaves a provided state.
 */
FOUNDATION_EXTERN FBFuture<NSNull *> *_Nonnull FBiOSTargetResolveLeavesState(id<FBiOSTarget> _Nonnull target, FBiOSTargetState state);
