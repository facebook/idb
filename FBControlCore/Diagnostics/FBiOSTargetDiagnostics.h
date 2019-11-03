/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDiagnostic.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDiagnostic;
@class FBDiagnosticBuilder;

/**
 The Name of the Video Log
 */
extern FBDiagnosticName const FBDiagnosticNameVideo;

/**
 The Name of the iOS System Log.
 */
extern FBDiagnosticName const FBDiagnosticNameSyslog;

/**
 The Name of the Screenshot Log.
 */
extern FBDiagnosticName const FBDiagnosticNameScreenshot;


/**
 A Base Class for Providing Diagnostics from a target.
 */
@interface FBiOSTargetDiagnostics : NSObject

/**
 The Designated Initializer

 @param storageDirectory the default location for persisting diagnostics to.
 @return a new Target Diagnostics instance.
 */
- (instancetype)initWithStorageDirectory:(NSString *)storageDirectory;

/**
 The default location for persisting Diagnostics to.
 */
@property (nonatomic, copy, readonly) NSString *storageDirectory;

/**
 The FBDiagnostic Instance from which all other diagnostics are derived.
 */
- (FBDiagnostic *)base;

/**
 A Video of the Simulator
 */
- (FBDiagnostic *)video;

/**
 The FBDiagnostic Builder from which all other diagnostics are derived.
 */
- (FBDiagnosticBuilder *)baseLogBuilder;

/**
 All of the FBDiagnostic instances for the Simulator.
 Prunes empty logs.

 @return an NSArray<FBDiagnostic> of all the Diagnostics associated with the Simulator.
 */
- (NSArray<FBDiagnostic *> *)allDiagnostics;

/**
 All of the FBDiagnostic instances for the Simulator, bucketed by diagnostic name.
 Prunes empty and unnamed logs

 @return a dictionary mapping diagnostic names to diagnostics.
 */
- (NSDictionary<NSString *, FBDiagnostic *> *)namedDiagnostics;

/**
 Fetches Diagnostics inside Application Containers.
 Looks inside the Home Directory of the Application.

 @param bundleID the Appliction to search for by Bundle ID. May be nil.
 @param filenames the Filenames of the Diagnostics to search for. Must not be nil.
 @param filenameGlobs the filename globs of the Diagnostics to search for. Must not be nil.
 @param globalFallback if YES, the entire Simulator will be searched in the event that the Application's Home Directory cannot be found.
 @return an Dictionary of all the successfully found diagnostics.
 */
- (NSArray<FBDiagnostic *> *)diagnosticsForApplicationWithBundleID:(nullable NSString *)bundleID withFilenames:(NSArray<NSString *> *)filenames withFilenameGlobs:(NSArray<NSString *> *)filenameGlobs fallbackToGlobalSearch:(BOOL)globalFallback;

/**
 A Predicate for FBDiagnostics that have content.
 */
+ (NSPredicate *)predicateForHasContent;

@end

NS_ASSUME_NONNULL_END
