/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import "FBXCTestDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Base class for bundle storage.
 */
@interface FBBundleStorage : NSObject

#pragma mark Public Methods

/**
 Checks the bundle is supported on the current target

 @param bundle Bundle to check
 @param error Set if the targets architecture isn't in the set supported by the bundle
 @return YES if the bundle can run on this target, NO otherwise
 */
- (BOOL)checkArchitecture:(FBBundleDescriptor *)bundle error:(NSError **)error;

/**
 Persist the bundle to storage.

 @param bundle the bundle to persist.
 @param error an error out for any error that occurs.
 */
- (nullable NSString *)saveBundle:(FBBundleDescriptor *)bundle error:(NSError **)error;

@end

/**
 Bundle storage for xctest.
 */
@interface FBXCTestBundleStorage : FBBundleStorage

#pragma mark Public Methods

/**
 Saves the relevant files from an extracted directory.

 @param baseDirectory the directory containing a bundle
 @param error an error out for any error that occurs.
 @return the bundle id of the installed test, or nil if failed
 */
- (nullable NSString *)saveBundleOrTestRunFromBaseDirectory:(NSURL *)baseDirectory error:(NSError **)error;

/**
 Saves a file

 @param filePath the file containing a bundle
 @param error an error out for any error that occurs.
 @return the bundle id of the installed test, or nil if failed
 */
- (nullable NSString *)saveBundleOrTestRun:(NSURL *)filePath error:(NSError **)error;

/**
 Get descriptors for all installed test bundles and xctestrun files.

 @param error Set if getting this bundle failed
 @return Set of FBXCTestDescriptors of all installed test bundles and xctestrun files
 */
- (nullable NSSet<id<FBXCTestDescriptor>> *)listTestDescriptorsWithError:(NSError **)error;

/**
 Get test descriptor by bundle id.

 @param bundleId Bundle id of test to get
 @return test descriptor of the test
 */
- (nullable id<FBXCTestDescriptor>)testDescriptorWithID:(NSString *)bundleId error:(NSError **)error;

@end

/**
 Bundle storage for applications.
 */
@interface FBApplicationBundleStorage : FBBundleStorage

#pragma mark Public Methods

/**
 The bundle ids of all persisted applications
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *persistedApplicationBundleIDs;

/**
 A mapping of bundle ids to persisted applications
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, FBApplicationBundle *> *persistedApplications;

@end

/**
 Class to manage storage of dynamic libraries that can be used for injection into processes
 */
@interface FBDylibStorage : FBBundleStorage

/**
 Relocates the dylib into storage.

 @param url the dylib url to relocate.
 @param error an error out for any error that occurs
 @return the path of the relocated file.
 */
- (nullable NSString *)saveDylibFromFile:(NSURL *)url error:(NSError **)error;

/**
 Interpolate the stored dylibs so that they can be replaced.

 @param environment the environment to interpolate.
 @return a dictionary with the replacements defined
 */
- (NSDictionary<NSString *, NSString *> *)interpolateDylibReplacements:(NSDictionary<NSString *, NSString *> *)environment;

@end

/**
 Class to manage storing of test and application bundles in the target's aux directory
 Test bundles are stored under TARGET_AUX_DIR/idb-test-bundles/TEST_BUNDLE_ID/TEST_BUNDLE.xctest
 Application bundles are stored under TARGET_AUX_DIR/idb-applications/APPLICATION_BUNDLE_ID
 */
@interface FBBundleStorageManager : NSObject

#pragma mark Initializers

/**
 The designated initializer

 @param target Target to store the test bundles in
 @param logger FBControlCoreLogger to use
 @param error an error out for any error that occurs in creating the storage
 @return a FBTestBundleStorageManager instance on success, nil otherwise.
 */
+ (nullable instancetype)managerForTarget:(id<FBiOSTarget>)target logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Properties

/**
 The xctest bundle storage
 */
@property (nonatomic, strong, readonly) FBXCTestBundleStorage *xctest;

/**
 The application bundle storage
 */
@property (nonatomic, strong, readonly) FBApplicationBundleStorage *application;

/**
 The dylib storage.
 */
@property (nonatomic, strong, readonly) FBDylibStorage *dylib;

@end

NS_ASSUME_NONNULL_END
