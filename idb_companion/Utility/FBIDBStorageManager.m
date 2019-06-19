/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBStorageManager.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBIDBError.h"
#import "FBStorageUtils.h"
#import "FBXCTestDescriptor.h"

@implementation FBInstalledArtifact

- (instancetype)initWithName:(NSString *)name uuid:(NSUUID *)uuid
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _uuid = uuid;

  return self;
}

@end

@implementation FBIDBStorage

#pragma mark Initializers

- (instancetype)initWithTarget:(id<FBiOSTarget>)target basePath:(NSURL *)basePath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _basePath = basePath;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Properties

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  NSMutableDictionary<NSString *, NSString *> *replacementMapping = NSMutableDictionary.dictionary;
  for (NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.basePath includingPropertiesForKeys:nil options:0 error:nil]) {
    replacementMapping[url.lastPathComponent] = url.path;
  }
  return replacementMapping;
}

@end

@implementation FBFileStorage

- (nullable FBInstalledArtifact *)saveFile:(NSURL *)url error:(NSError **)error
{
  NSURL *destination = [self.basePath URLByAppendingPathComponent:url.lastPathComponent];
  [self.logger logFormat:@"Persisting %@ to %@", url.lastPathComponent, destination];
  if (![NSFileManager.defaultManager copyItemAtURL:url toURL:destination error:error]) {
    return nil;
  }
  [self.logger logFormat:@"Persisted %@", destination.lastPathComponent];
  return [[FBInstalledArtifact alloc] initWithName:destination.lastPathComponent uuid:nil];
}

@end

@implementation FBBundleStorage

#pragma mark Initializers

- (instancetype)initWithTarget:(id<FBiOSTarget>)target basePath:(NSURL *)basePath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger relocateLibraries:(BOOL)relocateLibraries
{
  self = [super initWithTarget:target basePath:basePath queue:queue logger:logger];
  if (!self) {
    return nil;
  }

  _relocateLibraries = relocateLibraries;

  return self;
}

#pragma mark Public

- (BOOL)checkArchitecture:(FBBundleDescriptor *)bundle error:(NSError **)error
{
  NSSet<NSString *> *bundleArchs = bundle.binary.architectures;
  NSString *targetArch = self.target.architecture;

  if (![bundleArchs containsObject:targetArch]) {
    return [[FBIDBError
      describeFormat:@"Targets architecture %@ not in the bundles supported architectures: %@", targetArch, bundleArchs.allObjects]
      failBool:error];
  }

  return YES;
}

- (FBFuture<FBInstalledArtifact *> *)saveBundle:(FBBundleDescriptor *)bundle
{
  // Check that the bundle matches the architecture of the target.
  NSError *error = nil;
  if (![self checkArchitecture:bundle error:&error]) {
    return [FBFuture futureWithError:error];
  }

  // Where the bundle will be copied to.
  NSURL *storageDirectory = [self.basePath URLByAppendingPathComponent:bundle.identifier];
  if (![self prepareDirectoryWithURL:storageDirectory error:&error]) {
    return [FBFuture futureWithError:error];
  }

  // Copy over bundle
  NSURL *sourceBundlePath = [NSURL fileURLWithPath:bundle.path];
  NSURL *destinationBundlePath = [storageDirectory URLByAppendingPathComponent:sourceBundlePath.lastPathComponent];
  [self.logger logFormat:@"Persisting %@ to %@", bundle.identifier, destinationBundlePath];
  if (![NSFileManager.defaultManager copyItemAtURL:sourceBundlePath toURL:destinationBundlePath error:&error]) {
    return [FBFuture futureWithError:error];
  }
  [self.logger logFormat:@"Persisted %@", bundle.identifier];

  FBInstalledArtifact *artifact = [[FBInstalledArtifact alloc] initWithName:bundle.identifier uuid:bundle.binary.uuid];
  if (!self.relocateLibraries) {
    return [FBFuture futureWithResult:artifact];
  }
  bundle = [FBBundleDescriptor bundleFromPath:destinationBundlePath.path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  return [[bundle
    updatePathsForRelocationWithCodesign:FBCodesignProvider.codeSignCommandWithAdHocIdentity logger:self.logger queue:self.queue]
    mapReplace:artifact];
}

#pragma mark Properties

- (NSSet<NSString *> *)persistedBundleIDs
{
  return [NSSet setWithArray:([NSFileManager.defaultManager contentsOfDirectoryAtPath:self.basePath.path error:nil] ?: @[])];
}

- (NSDictionary<NSString *, FBBundleDescriptor *> *)persistedBundles
{
  NSMutableDictionary<NSString *, FBBundleDescriptor *> *mapping = [NSMutableDictionary dictionary];
  for (NSURL *directory in [NSFileManager.defaultManager enumeratorAtURL:self.basePath includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil]) {
    NSString *key = directory.lastPathComponent;
    NSError *error = nil;
    NSURL *bundlePath = [FBStorageUtils findUniqueFileInDirectory:directory error:nil];
    if (!bundlePath) {
      continue;
    }
    FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:bundlePath.path error:&error];
    if (!bundle) {
      [self.logger logFormat:@"Failed to get bundle info for bundle at path %@", bundlePath];
    }
    mapping[key] = bundle;
  }
  return mapping;
}

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  NSDictionary<NSString *, FBBundleDescriptor *> *persistedBundles = self.persistedBundles;
  NSMutableDictionary<NSString *, NSString *> *mapping = NSMutableDictionary.dictionary;
  for (NSString *name in persistedBundles) {
    FBBundleDescriptor *bundle = persistedBundles[name];
    if (bundle.identifier) {
      mapping[bundle.identifier] = bundle.path;
    }
    if (bundle.binary.uuid) {
      mapping[bundle.binary.uuid.UUIDString] = bundle.path;
    }
  }
  return mapping;
}

#pragma mark Private

- (BOOL)prepareDirectoryWithURL:(NSURL *)url error:(NSError **)error
{
  // Clear old test
  if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
    if (![NSFileManager.defaultManager removeItemAtURL:url error:error]) {
      return NO;
    }
  }
  // Recreate directory
  if (![NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:error]) {
    return NO;
  }
  return YES;
}

@end

static NSString *const XctestExtension = @"xctest";
static NSString *const XctestRunExtension = @"xctestrun";

@implementation FBXCTestBundleStorage

#pragma mark Public

- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRunFromBaseDirectory:(NSURL *)baseDirectory
{
  // Find .xctest or .xctestrun in directory.
  NSError *error = nil;
  NSDictionary<NSString *, NSSet<NSURL *> *> *buckets = [FBStorageUtils bucketFilesWithExtensions:[NSSet setWithArray:@[XctestExtension, XctestRunExtension]] inDirectory:baseDirectory error:&error];
  if (!buckets) {
    return [FBFuture futureWithError:error];
  }
  NSArray<NSURL *> *bucket = buckets[XctestExtension].allObjects;
  NSURL *xctestBundleURL = bucket.firstObject;
  if (bucket.count > 1) {
    return [[FBControlCoreError
      describeFormat:@"Multiple files with .xctest extension: %@", [FBCollectionInformation oneLineDescriptionFromArray:bucket]]
      failFuture];
  }
  bucket = buckets[XctestRunExtension].allObjects;
  NSURL *xctestrunURL = bucket.firstObject;
  if (bucket.count > 1) {
    return [[FBControlCoreError
      describeFormat:@"Multiple files with .xctestrun extension: %@", [FBCollectionInformation oneLineDescriptionFromArray:bucket]]
      failFuture];
  }
  if (!xctestBundleURL && !xctestrunURL) {
    return [[FBIDBError
      describeFormat:@"Neither a .xctest bundle or .xctestrun file provided: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:buckets]]
      failFuture];
  }

  if (xctestBundleURL) {
    return [self saveTestBundle:xctestBundleURL];
  }
  if (xctestrunURL) {
    return [self saveTestRun:xctestrunURL];
  }
  return [[FBIDBError
    describeFormat:@".xctest bundle (%@) or .xctestrun (%@) file was not saved", xctestBundleURL, xctestrunURL]
    failFuture];
}

- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRun:(NSURL *)filePath
{
  // save .xctest or .xctestrun
  if ([filePath.pathExtension isEqualToString:XctestExtension]) {
    return [self saveTestBundle:filePath];
  }
  if ([filePath.pathExtension isEqualToString:XctestRunExtension]) {
    return [self saveTestRun:filePath];
  }
  return [[FBControlCoreError
    describeFormat:@"The path extension (%@) of the provided bundle (%@) is not .xctest or .xctestrun", filePath.pathExtension, filePath]
    failFuture];
}

- (NSSet<id<FBXCTestDescriptor>> *)listTestDescriptorsWithError:(NSError **)error
{
  NSMutableSet<id<FBXCTestDescriptor>> *testDescriptors = [[NSMutableSet alloc] init];

  // Get xctest bundles
  NSSet<NSURL *> *testURLS = [self listTestBundlesWithError:error];
  if (!testURLS) {
    return nil;
  } else if (error) {
    *error = nil;
  }
  // Get xctestrun files
  NSSet<NSURL *> *xcTestRunURLS = [self listXCTestRunFilesWithError:error];
  if (!xcTestRunURLS) {
    return nil;
  } else if (error) {
    *error = nil;
  }

  // Get info out of xctest bundles
  for (NSURL *testURL in testURLS) {
    FBBundleDescriptor *bundle = [FBBundleDescriptor bundleWithFallbackIdentifierFromPath:testURL.path error:error];
    if (!bundle) {
      if (error) {
        [self.logger.error log:(*error).description];
      }
      continue;
    }

    id<FBXCTestDescriptor> testDescriptor = [[FBXCTestBootstrapDescriptor alloc] initWithURL:testURL name:bundle.name testBundle:bundle];

    [testDescriptors addObject:testDescriptor];
  }

  // Get info out of xctestrun files
  for (NSURL *xcTestRunURL in xcTestRunURLS) {
    NSArray<id<FBXCTestDescriptor>> *descriptors = [self getXCTestRunDescriptorsFromURL:xcTestRunURL];
    [testDescriptors addObjectsFromArray:descriptors];
  }

  return testDescriptors;
}

- (id<FBXCTestDescriptor>)testDescriptorWithID:(NSString *)bundleId error:(NSError **)error
{
  NSSet<id<FBXCTestDescriptor>> *testDescriptors = [self listTestDescriptorsWithError:error];
  for (id<FBXCTestDescriptor> testDescriptor in testDescriptors) {
    if ([[testDescriptor testBundleID] isEqualToString: bundleId]) {
      return testDescriptor;
    }
  }

  return [[FBIDBError describeFormat:@"Couldn't find test with id: %@", bundleId] fail:error];
}

#pragma mark Private

- (NSSet<NSURL *> *)listTestBundlesWithError:(NSError **)error
{
  return [self listXCTestContentsWithExtension:XctestExtension error:error];
}

- (NSSet<NSURL *> *)listXCTestRunFilesWithError:(NSError **)error
{
  return [self listXCTestContentsWithExtension:XctestRunExtension error:error];
}

- (NSURL *)xctestBundleWithID:(NSString *)bundleID error:(NSError **)error
{
  NSURL *directory = [self.basePath URLByAppendingPathComponent:bundleID];
  return [FBStorageUtils findFileWithExtension:XctestExtension atURL:directory error:error];
}

- (NSSet<NSURL *> *)listXCTestContentsWithExtension:(NSString *)extention error:(NSError **)error
{
  NSArray<NSURL *> *directories = [NSFileManager.defaultManager
    contentsOfDirectoryAtURL:self.basePath
    includingPropertiesForKeys:nil
    options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
    error:error];
  if (!directories) {
    return [[FBIDBError describe:@"Error reading test bundle base directory"] fail:error];
  }

  NSMutableSet<NSURL *> *tests = [NSMutableSet setWithCapacity:directories.count];
  for (NSURL *innerDirectory in directories) {
    NSURL *bundleURL = [FBStorageUtils findFileWithExtension:extention atURL:innerDirectory error:error];
    if (bundleURL) {
      [tests addObject:bundleURL];
    }
  }

  return tests;
}

- (id<FBXCTestDescriptor>)testDescriptorWithURL:(NSURL *)url error:(NSError **)error
{
  NSSet<id<FBXCTestDescriptor>> *testDescriptors = [self listTestDescriptorsWithError:error];
  for (id<FBXCTestDescriptor> testDescriptor in testDescriptors) {
    if ([[[testDescriptor url] absoluteString] isEqualToString:[url absoluteString]]) {
      return testDescriptor;
    }
  }

  return [[FBIDBError describeFormat:@"Couldn't find test with url: %@", url] fail:error];
}

- (NSArray<id<FBXCTestDescriptor>> *)getXCTestRunDescriptorsFromURL:(NSURL *)xcTestRunURL
{
  NSMutableArray<id<FBXCTestDescriptor>> *descriptors = [[NSMutableArray alloc] init];
  NSError *error;

  NSDictionary *contentDict = [NSDictionary dictionaryWithContentsOfURL:xcTestRunURL];
  for (NSString *testName in contentDict) {
    NSDictionary *testDict = [contentDict objectForKey:testName];
    NSNumber *useArtifacts = testDict[@"UseDestinationArtifacts"];
    if ([useArtifacts isKindOfClass:[NSNumber class]] && [useArtifacts boolValue]) {
      NSString *hostIdentifier = testDict[@"TestHostBundleIdentifier"];
      NSString *testIdentifier = testDict[@"FB_TestBundleIdentifier"];
      if (!hostIdentifier) {
        [self.logger.error log:@"Using UseDestinationArtifacts requires TestHostBundleIdentifier"];
        continue;
      }
      if (!testIdentifier) {
        [self.logger.error log:@"Using UseDestinationArtifacts requires FB_TestBundleIdentifier"];
        continue;
      }
      FBBundleDescriptor *testBundle = [[FBBundleDescriptor alloc] initWithName:testIdentifier identifier:testIdentifier path:@"" binary:nil];
      FBBundleDescriptor *hostBundle = [[FBBundleDescriptor alloc] initWithName:hostIdentifier identifier:hostIdentifier path:@"" binary:nil];
      id<FBXCTestDescriptor> descriptor = [[FBXCodebuildTestRunDescriptor alloc] initWithURL:xcTestRunURL name:testName testBundle:testBundle testHostBundle:hostBundle];
      [descriptors addObject:descriptor];
      continue;
    }
    NSString *testHostPath = [testDict objectForKey:@"TestHostPath"];
    NSString *testRoot = [[xcTestRunURL path] stringByDeletingLastPathComponent];
    testHostPath = [testRoot stringByAppendingPathComponent:[testHostPath lastPathComponent]];

    // Get test bundle path and replace __TESTROOT__ and __TESTHOST__ in it
    NSString *testBundlePath = [testDict objectForKey:@"TestBundlePath"];
    testBundlePath = [testBundlePath
      stringByReplacingOccurrencesOfString:@"__TESTROOT__"
      withString:testRoot];
    testBundlePath = [testBundlePath
      stringByReplacingOccurrencesOfString:@"__TESTHOST__"
      withString:testHostPath];

    // Get the bundles for test host and test app
    FBBundleDescriptor *testHostBundle = [FBBundleDescriptor bundleFromPath:testHostPath error:&error];
    if (!testHostBundle) {
      [self.logger.error log:error.description];
      continue;
    }
    FBBundleDescriptor *testBundle = [FBBundleDescriptor bundleFromPath:testBundlePath error:&error];
    if (!testBundle) {
      [self.logger.error log:error.description];
      continue;
    }
    id<FBXCTestDescriptor> descriptor = [[FBXCodebuildTestRunDescriptor alloc] initWithURL:xcTestRunURL name:testName testBundle:testBundle testHostBundle:testHostBundle];
    [descriptors addObject:descriptor];
  }

  return descriptors;
}

- (FBFuture<FBInstalledArtifact *> *)saveTestBundle:(NSURL *)testBundleURL
{
  // Test Bundles don't always have a bundle id, so fallback to another name if it's not there.
  NSError *error = nil;
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleWithFallbackIdentifierFromPath:testBundleURL.path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  return [self saveBundle:bundle];
}

- (FBFuture<FBInstalledArtifact *> *)saveTestRun:(NSURL *)XCTestRunURL
{
  // Delete old xctestrun with the same id if it exists
  NSArray<id<FBXCTestDescriptor>> *descriptors = [self getXCTestRunDescriptorsFromURL:XCTestRunURL];
  if (descriptors.count != 1) {
    return [[FBIDBError
      describeFormat:@"Expected exactly one test in the xctestrun file, got: %lu", descriptors.count]
      failFuture];
  }

  id<FBXCTestDescriptor> descriptor = descriptors[0];
  NSError *error = nil;
  id<FBXCTestDescriptor> toDelete = [self testDescriptorWithID:descriptor.testBundleID error:&error];
  if (toDelete) {
    if (![NSFileManager.defaultManager removeItemAtURL:[toDelete.url URLByDeletingLastPathComponent] error:&error]) {
      return [FBFuture futureWithError:error];
    }
  }

  NSString *uuidString = [[NSUUID UUID] UUIDString];
  NSURL *newPath = [self.basePath URLByAppendingPathComponent:uuidString];

  if (![self prepareDirectoryWithURL:newPath error:&error]) {
    return [FBFuture futureWithError:error];
  }

  // Get the directory containing the xctestrun file and its contents
  NSURL *dir = [XCTestRunURL URLByDeletingLastPathComponent];
  NSArray<NSURL *> *contents = [NSFileManager.defaultManager
    contentsOfDirectoryAtURL:dir
    includingPropertiesForKeys:nil
    options:0
    error:&error];
  if (!contents) {
    return [FBFuture futureWithError:error];
  }

  // Copy all files
  for (NSURL *url in contents) {
    if (![NSFileManager.defaultManager moveItemAtURL:url toURL:[newPath URLByAppendingPathComponent:url.lastPathComponent] error:&error]) {
      return [FBFuture futureWithError:error];
    }
  }

  FBInstalledArtifact *artifact = [[FBInstalledArtifact alloc] initWithName:[descriptor testBundleID] uuid:nil];
  return [FBFuture futureWithResult:artifact];
}

@end

@implementation FBIDBStorageManager

#pragma mark Initializers

+ (NSURL *)prepareStoragePathWithName:(NSString *)name target:(id<FBiOSTarget>)target error:(NSError **)error
{
  NSError *innerError = nil;
  NSURL *xctestBasePath = [[NSURL fileURLWithPath:target.auxillaryDirectory] URLByAppendingPathComponent:name];
  if (![NSFileManager.defaultManager createDirectoryAtURL:xctestBasePath withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBIDBError
      describeFormat:@"Failed to create xctest storage location %@", xctestBasePath]
      causedBy:innerError]
      fail:error];
  }
  return xctestBasePath;
}

+ (nullable instancetype)managerForTarget:(id<FBiOSTarget>)target logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.idb.bundle_storage", DISPATCH_QUEUE_SERIAL);

  NSURL *basePath = [self prepareStoragePathWithName:@"idb-test-bundles" target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBXCTestBundleStorage *xctest = [[FBXCTestBundleStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger relocateLibraries:NO];

  basePath = [self prepareStoragePathWithName:@"idb-applications" target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBBundleStorage *application = [[FBBundleStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger relocateLibraries:NO];

  basePath = [self prepareStoragePathWithName:@"idb-dylibs" target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBFileStorage *dylib = [[FBFileStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger];

  basePath = [self prepareStoragePathWithName:@"idb-dsyms" target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBFileStorage *dsym = [[FBFileStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger];

  basePath = [self prepareStoragePathWithName:@"idb-frameworks" target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBBundleStorage *framework = [[FBBundleStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger relocateLibraries:YES];

  return [[self alloc] initWithXctest:xctest application:application dylib:dylib dsym:dsym framework:framework logger:logger];
}

- (instancetype)initWithXctest:(FBXCTestBundleStorage *)xctest application:(FBBundleStorage *)application dylib:(FBFileStorage *)dylib dsym:(FBFileStorage *)dsym framework:(FBBundleStorage *)framework logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _xctest = xctest;
  _application = application;
  _dylib = dylib;
  _dsym = dsym;
  _framework = framework;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (NSDictionary<NSString *, NSString *> *)interpolateEnvironmentReplacements:(NSDictionary<NSString *, NSString *> *)environment
{
  [self.logger logFormat:@"Original environment: %@", environment];
  NSDictionary<NSString *, NSString *> *nameToPath = [self replacementMapping];
  [self.logger logFormat:@"Existing replacement mapping: %@", nameToPath];
  NSMutableDictionary<NSString *, NSString *> *interpolatedEnvironment = [NSMutableDictionary dictionaryWithCapacity:environment.count];
  for (NSString *name in environment.allKeys) {
    NSString *value = environment[name];
    for (NSString *interpolationName in nameToPath.allKeys) {
      NSString *interpolationValue = nameToPath[interpolationName];
      value = [value stringByReplacingOccurrencesOfString:interpolationName withString:interpolationValue];
    }
    interpolatedEnvironment[name] = value;
  }
  [self.logger logFormat:@"Interpolated environment: %@", interpolatedEnvironment];
  return interpolatedEnvironment;
}

- (NSArray<NSString *> *)interpolateArgumentReplacements:(NSArray<NSString *> *)arguments
{
  [self.logger logFormat:@"Original arguments: %@", arguments];
  NSDictionary<NSString *, NSString *> *nameToPath = [self replacementMapping];
  [self.logger logFormat:@"Existing replacement mapping: %@", nameToPath];
  NSMutableArray<NSString *> *interpolatedArguments = [NSMutableArray arrayWithArray:arguments];
  [arguments enumerateObjectsUsingBlock:^(NSString *argument, NSUInteger idx, BOOL *stop) {
    [interpolatedArguments replaceObjectAtIndex:idx withObject:nameToPath[argument] ?: argument];
  }];
  [self.logger logFormat:@"Interpolated arguments: %@", interpolatedArguments];
  return interpolatedArguments;
}

#pragma mark Private

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  NSMutableDictionary<NSString *, NSString *> *combined = NSMutableDictionary.dictionary;
  for (NSDictionary<NSString *, NSString *> *replacementMapping in @[self.application.replacementMapping, self.dylib.replacementMapping, self.framework.replacementMapping, self.dsym.replacementMapping]) {
    [combined addEntriesFromDictionary:replacementMapping];
  }
  return combined;
}

@end
