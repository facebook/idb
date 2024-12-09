/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IdbTestBundlesFolder;
extern NSString *const IdbApplicationsFolder;
extern NSString *const IdbDylibsFolder;
extern NSString *const IdbDsymsFolder;
extern NSString *const IdbFrameworksFolder;

@protocol FBControlCoreLogger;
@protocol FBXCTestDescriptor;

/**
 A wrapper around an installed artifact
 */
@interface FBInstalledArtifact : NSObject

/**
 The name of the installed artifact.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The UDID of the installed artifact (if present).
 */
@property (nonatomic, copy, nullable, readonly) NSUUID *uuid;

/**
 The absolute path to the artifact
 */
@property (nonatomic, copy, readonly) NSURL *path;

/**
 The designated initializer.

 @param name the name of the installed artifact.
 @param uuid the udid of the installed artifact
 @param path the absolute path to the installed artifact
 */
- (instancetype)initWithName:(NSString *)name uuid:(nullable NSUUID *)uuid path:(NSURL *)path;

@end

/**
 The base class for storage in idb.
 */
@interface FBIDBStorage : NSObject

#pragma mark Properties

/**
 The target that is being stored against.
 */
@property (nonatomic, strong, readonly) id<FBiOSTarget> target;

/**
 The base path of the storage.
 */
@property (nonatomic, strong, readonly) NSURL *basePath;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The queue to use.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 A mapping of storage name to local path replacement.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *replacementMapping;

/**
 Exposes the receiver as an FBFileContainer instance.

 @return a FBFileContainer instance.
 */
- (id<FBFileContainer>)asFileContainer;

/**
 Cleans all storage

 @param error set if cleaning fails
 @return bool representing success
 */
- (BOOL)clean:(NSError **)error;

@end

/**
 Storage for files
 */
@interface FBFileStorage : FBIDBStorage

#pragma mark Public Methods

/**
 Relocates the file into storage.

 @param url the url to relocate.
 @param error an error out for any error that occurs
 @return the installed artifact info.
 */
- (nullable FBInstalledArtifact *)saveFile:(NSURL *)url error:(NSError **)error;

/**
 Relocates the file into storage and places it into UUID like parent directory to prevent overwrites.

 @param url the url to relocate.
 @param error an error out for any error that occurs
 @return the installed artifact info.
 */
- (nullable FBInstalledArtifact *)saveFileInUniquePath:(NSURL *)url error:(NSError **)error;

@end

/**
 Base class for bundle storage.
 */
@interface FBBundleStorage : FBIDBStorage

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
 @return a future of the persisted bundle info.
 */
- (FBFuture<FBInstalledArtifact *> *)saveBundle:(FBBundleDescriptor *)bundle;

#pragma mark Properties

/**
 The Bundle IDs of all installed bundles.
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *persistedBundleIDs;

/**
 A mapping of keys that identify bundles, to the bundle descriptors.
 These keys compromise:
 - The LC_UUID of the Bundle.
 - The Bundle ID of the Bundle.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, FBBundleDescriptor *> *persistedBundles;

/**
 Whether or not to perform manual relocation of libraries.
 */
@property (nonatomic, assign, readonly) BOOL relocateLibraries;

@end

/**
 Bundle storage for xctest.
 */
@interface FBXCTestBundleStorage : FBBundleStorage

#pragma mark Public Methods

/**
 Stores a test bundle, based on a containing directory.
 This is useful when the test bundle is extracted to a temporary directory, because it came from an archive.

 @param baseDirectory the directory containing the test bundle.
 @return the bundle id of the installed test, or nil if failed
 */
- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRunFromBaseDirectory:(NSURL *)baseDirectory skipSigningBundles:(BOOL)skipSigningBundles;

/**
 Stores a test bundle, based on the file path of the actual test bundle.
 This is useful when the test bundle is from an existing and local file path, instead of passed in an archive.

 @param filePath the file path of the bundle.
 @param skipSigningBundles pass true to skip signing xctest bundles.
 @return the bundle id of the installed test, or nil if failed
 */
- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRun:(NSURL *)filePath skipSigningBundles:(BOOL)skipSigningBundles;

/**
 Get descriptors for all installed test bundles and xctestrun files.

 @param error Set if getting this bundle failed
 @return List of FBXCTestDescriptors of all installed test bundles and xctestrun files
 */
- (nullable NSArray<id<FBXCTestDescriptor>> *)listTestDescriptorsWithError:(NSError **)error;

/**
 Get test descriptor by bundle id.

 @param bundleId Bundle id of test to get
 @return test descriptor of the test
 */
- (nullable id<FBXCTestDescriptor>)testDescriptorWithID:(NSString *)bundleId error:(NSError **)error;

/**
 Get test run descriptors from xctestrun file.

 @param xctestrunURL URL of xctestrun file
 @return test descriptor of the test
 */
- (nullable NSArray<id<FBXCTestDescriptor>> *)getXCTestRunDescriptorsFromURL:(NSURL *)xctestrunURL error:(NSError **)error;

@end

/**
 Class to manage storing of artifacts for a particular target
 Each kind of stored artifact is placed in a separate directory and managed by a separate class.
 */
@interface FBIDBStorageManager : NSObject

#pragma mark Initializers

/**
 The designated initializer

 @param target Target to store the test bundles in
 @param logger FBControlCoreLogger to use
 @param error an error out for any error that occurs in creating the storage
 @return a FBTeststorageManager instance on success, nil otherwise.
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
@property (nonatomic, strong, readonly) FBBundleStorage *application;

/**
 The dylib storage.
 */
@property (nonatomic, strong, readonly) FBFileStorage *dylib;

/**
 The dSYM storage.
 */
@property (nonatomic, strong, readonly) FBFileStorage *dsym;

/**
 The Frameworks storage.
 */
@property (nonatomic, strong, readonly) FBBundleStorage *framework;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

#pragma mark Public Methods

/**
 Interpolate path replacements

 @return a dictionary with the replacements defined
 */
- (NSDictionary<NSString *, NSString *> *)replacementMapping;

/**
 Interpolate any bundle names in the arguments with bundle paths.

 @param arguments the arguments to interpolate.
 @return an array with the replacement defined
 */
- (nullable NSArray<NSString *> *)interpolateArgumentReplacements:(nullable NSArray<NSString *> *)arguments;

/**
 Cleans all storage

 @param error set if cleaning fails
 @return bool representing success
 */
- (BOOL)clean:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
