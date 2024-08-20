/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBStorageManager.h"

#import "FBIDBError.h"
#import "FBXCTestDescriptor.h"
#import "FBXCTestRunFileReader.h"

NSString *const IdbTestBundlesFolder = @"idb-test-bundles";
NSString *const IdbApplicationsFolder = @"idb-applications";
NSString *const IdbDylibsFolder = @"idb-dylibs";
NSString *const IdbDsymsFolder = @"idb-dsyms";
NSString *const IdbFrameworksFolder = @"idb-frameworks";

@implementation FBInstalledArtifact

- (instancetype)initWithName:(NSString *)name uuid:(NSUUID *)uuid path:(NSURL *)path
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _uuid = uuid;
  _path = path;

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

#pragma mark Methods

- (BOOL)clean:(NSError **)error
{
  for (NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.basePath includingPropertiesForKeys:nil options:0 error:nil]) {
    if (![NSFileManager.defaultManager removeItemAtPath:url.path error:error]) {
      return NO;
    }
  }
  return YES;
}

- (id<FBFileContainer>)asFileContainer
{
  return [FBFileContainer fileContainerForBasePath:self.basePath.path];
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
  return [self copyInto:self.basePath from:url error:error];
}

- (nullable FBInstalledArtifact *)saveFileInUniquePath:(NSURL *)url error:(NSError **)error
{
  NSURL *baseURL = self.basePath;
  baseURL = [baseURL URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  if (![NSFileManager.defaultManager createDirectoryAtURL:baseURL withIntermediateDirectories:YES attributes:nil error:error]) {
    return nil;
  }
  return [self copyInto:baseURL from:url error:error];
}

#pragma mark Private Methods

- (nullable FBInstalledArtifact *)copyInto:(NSURL *)basePath from:(NSURL *)fromURL error:(NSError **)error
{
  NSURL *destination = [basePath URLByAppendingPathComponent:fromURL.lastPathComponent];
  [self.logger logFormat:@"Persisting %@ to %@", fromURL.lastPathComponent, destination];
  if (![NSFileManager.defaultManager copyItemAtURL:fromURL toURL:destination error:error]) {
    return nil;
  }
  [self.logger logFormat:@"Persisted %@", destination.lastPathComponent];
  return [[FBInstalledArtifact alloc] initWithName:destination.lastPathComponent uuid:nil path:destination];
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
  NSSet<FBArchitecture> *binaryArchitectures = bundle.binary.architectures;
  NSArray<FBArchitecture> *targetArchs = self.target.architectures;
  NSSet<FBArchitecture> *supportedArchitectures = [FBiOSTargetConfiguration baseArchsToCompatibleArch:targetArchs];

  const BOOL containsExactArch = [binaryArchitectures intersectsSet:supportedArchitectures];
  // arm64 binaries are acceptable on arm64e devices
  const BOOL arm64eEquivalent = [targetArchs containsObject:@"arm64e"] && [binaryArchitectures containsObject:@"arm64"];

  if (!(containsExactArch || arm64eEquivalent)) {
    return [[FBIDBError
             describeFormat:@"The supported architectures of the target %@ do not intersect with any architectures in the bundle: %@", [FBCollectionInformation oneLineDescriptionFromArray:supportedArchitectures.allObjects], [FBCollectionInformation oneLineDescriptionFromArray:binaryArchitectures.allObjects]]
            failBool:error];
  }

  return YES;
}

- (FBFuture<FBInstalledArtifact *> *)saveBundle:(FBBundleDescriptor *)bundle
{
  return [self saveBundle:bundle usingSymlink:YES skipSigningBundles:NO];
}

- (FBFuture<FBInstalledArtifact *> *)saveBundle:(FBBundleDescriptor *)bundle usingSymlink:(BOOL)useSymlink skipSigningBundles:(BOOL)skipSigningBundles
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

  NSURL *sourceBundlePath = [NSURL fileURLWithPath:bundle.path];
  NSURL *destinationBundlePath = [storageDirectory URLByAppendingPathComponent:sourceBundlePath.lastPathComponent];
  if (useSymlink) {
    // Symlink the bundle
    [self.logger logFormat:@"Symlink %@ to %@", bundle.identifier, destinationBundlePath];
    if (![NSFileManager.defaultManager createSymbolicLinkAtURL:destinationBundlePath withDestinationURL:sourceBundlePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
  } else {
    // Move the bundle
    [self.logger logFormat:@"Moving %@ to %@", bundle.identifier, destinationBundlePath];
    if (![NSFileManager.defaultManager moveItemAtURL:sourceBundlePath toURL:destinationBundlePath error:&error]) {
      return [FBFuture futureWithError:error];
    }
    [self.logger logFormat:@"Moved %@", bundle.identifier];
  }

  FBInstalledArtifact *artifact = [[FBInstalledArtifact alloc] initWithName:bundle.identifier uuid:bundle.binary.uuid path:destinationBundlePath];
  if (!self.relocateLibraries || ![self.target requiresBundlesToBeSigned] || skipSigningBundles) {
    return [FBFuture futureWithResult:artifact];
  }
  bundle = [FBBundleDescriptor bundleFromPath:destinationBundlePath.path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  FBCodesignProvider *provider = [FBCodesignProvider codeSignCommandWithAdHocIdentityWithLogger:self.logger];
  return [[bundle
    updatePathsForRelocationWithCodesign:provider logger:self.logger queue:self.queue]
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

- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRunFromBaseDirectory:(NSURL *)baseDirectory skipSigningBundles:(BOOL)skipSigningBundles
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
    return [self saveTestBundle:xctestBundleURL usingSymlink:NO skipSigningBundles:skipSigningBundles];
  }
  if (xctestrunURL) {
    return [self saveTestRun:xctestrunURL];
  }
  return [[FBIDBError
    describeFormat:@".xctest bundle (%@) or .xctestrun (%@) file was not saved", xctestBundleURL, xctestrunURL]
    failFuture];
}

- (FBFuture<FBInstalledArtifact *> *)saveBundleOrTestRun:(NSURL *)filePath skipSigningBundles:(BOOL)skipSigningBundles
{
  // save .xctest or .xctestrun
  if ([filePath.pathExtension isEqualToString:XctestExtension]) {
    return [self saveTestBundle:filePath usingSymlink:YES skipSigningBundles:skipSigningBundles];
  }
  if ([filePath.pathExtension isEqualToString:XctestRunExtension]) {
    return [self saveTestRun:filePath];
  }
  return [[FBControlCoreError
    describeFormat:@"The path extension (%@) of the provided bundle (%@) is not .xctest or .xctestrun", filePath.pathExtension, filePath]
    failFuture];
}

- (NSArray<id<FBXCTestDescriptor>> *)listTestDescriptorsWithError:(NSError **)error
{
  NSMutableArray<id<FBXCTestDescriptor>> *testDescriptors = [[NSMutableArray alloc] init];

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
    NSArray<id<FBXCTestDescriptor>> *descriptors = [self getXCTestRunDescriptorsFromURL:xcTestRunURL error:error];
    if (!descriptors) {
      return nil;
    }
    [testDescriptors addObjectsFromArray:descriptors];
  }

  return [NSArray arrayWithArray:testDescriptors];
}

- (id<FBXCTestDescriptor>)testDescriptorWithID:(NSString *)bundleId error:(NSError **)error
{
  NSArray<id<FBXCTestDescriptor>> *testDescriptors = [self listTestDescriptorsWithError:error];
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
  NSArray<id<FBXCTestDescriptor>> *testDescriptors = [self listTestDescriptorsWithError:error];
  for (id<FBXCTestDescriptor> testDescriptor in testDescriptors) {
    if ([[[testDescriptor url] absoluteString] isEqualToString:[url absoluteString]]) {
      return testDescriptor;
    }
  }

  return [[FBIDBError describeFormat:@"Couldn't find test with url: %@", url] fail:error];
}

- (nullable NSArray<id<FBXCTestDescriptor>> *)getXCTestRunDescriptorsFromURL:(NSURL *)xctestrunURL error:(NSError **)error
{
  NSDictionary<NSString *, id> *contentDict = [FBXCTestRunFileReader readContentsOf:xctestrunURL expandPlaceholderWithPath:self.target.auxillaryDirectory error:error];
  if (!contentDict) {
    return nil;
  }
  NSDictionary<NSString *, NSNumber *> *xctestrunMetadata = contentDict[@"__xctestrun_metadata__"];
  // The legacy format of xctestrun file does not contain __xctestrun_metadata__
  if (xctestrunMetadata) {
    [self.logger.info logFormat:@"Using xctestrun format version: %@", xctestrunMetadata[@"FormatVersion"]];
    return [self getDescriptorsFrom:contentDict with:xctestrunURL];
  } else {
    [self.logger.info log:@"Using the legacy xctestrun file format"];
    return [self legacyGetDescriptorsFrom:contentDict with:xctestrunURL];
  }
}

// xctestrun for Xcode 11+
- (NSArray<id<FBXCTestDescriptor>> *)getDescriptorsFrom:(NSDictionary<NSString *, NSDictionary *> *)xctestrunContents with:(NSURL *)xctestrunURL
{
  NSMutableArray<id<FBXCTestDescriptor>> *descriptors = [[NSMutableArray alloc] init];
  for (NSString *field in xctestrunContents) {
    [self.logger.info logFormat:@"Checking the %@ field to extract test descriptors", field];
    if ([field isEqualToString:@"__xctestrun_metadata__"] || [field isEqualToString:@"CodeCoverageBuildableInfos"]) {
      continue;
    }
    id<FBXCTestDescriptor> descriptor = [self getDescriptorFor:field from:xctestrunContents with:xctestrunURL];
    if (descriptor != nil) {
      [descriptors addObject:descriptor];
    }
  }
  return descriptors;
}

// xctestrun before Xcode 11
- (NSArray<id<FBXCTestDescriptor>> *)legacyGetDescriptorsFrom:(NSDictionary<NSString *, NSDictionary *> *)xctestrunContents with:(NSURL *)xctestrunURL
{
  NSMutableArray<id<FBXCTestDescriptor>> *descriptors = [[NSMutableArray alloc] init];
  for (NSString *testTarget in xctestrunContents) {
    id<FBXCTestDescriptor> descriptor = [self getDescriptorFor:testTarget from:xctestrunContents with:xctestrunURL];
    if (descriptor != nil) {
      [descriptors addObject:descriptor];
    }
  }
  return descriptors;
}

- (nullable id<FBXCTestDescriptor>)getDescriptorFor:(NSString *)testTarget from:(NSDictionary<NSString *, NSDictionary *> *)xctestrunContents with:(NSURL *)xctestrunURL
{
  NSError *error;

  NSDictionary<NSString *, id> *testTargetProperties = [xctestrunContents objectForKey:testTarget];
  NSNumber *useArtifacts = testTargetProperties[@"UseDestinationArtifacts"];
  if ([useArtifacts isKindOfClass:[NSNumber class]] && [useArtifacts boolValue]) {
    NSString *hostIdentifier = testTargetProperties[@"TestHostBundleIdentifier"];
    NSString *testIdentifier = testTargetProperties[@"FB_TestBundleIdentifier"];
    if (!hostIdentifier) {
      [self.logger.error log:@"Using UseDestinationArtifacts requires TestHostBundleIdentifier"];
      return nil;
    }
    if (!testIdentifier) {
      [self.logger.error log:@"Using UseDestinationArtifacts requires FB_TestBundleIdentifier"];
      return nil;
    }
    FBBundleDescriptor *testBundle = [[FBBundleDescriptor alloc] initWithName:testIdentifier identifier:testIdentifier path:@"" binary:nil];
    FBBundleDescriptor *hostBundle = [[FBBundleDescriptor alloc] initWithName:hostIdentifier identifier:hostIdentifier path:@"" binary:nil];
    return [[FBXCodebuildTestRunDescriptor alloc] initWithURL:xctestrunURL name:testTarget testBundle:testBundle testHostBundle:hostBundle];
  }
  NSString *testHostPath = [testTargetProperties objectForKey:@"TestHostPath"];
  NSString *testBundlePath = [testTargetProperties objectForKey:@"TestBundlePath"];
  // Get the bundles for test host and test app
  FBBundleDescriptor *testHostBundle = [FBBundleDescriptor bundleFromPath:testHostPath error:&error];
  if (!testHostBundle) {
    [self.logger.error log:error.description];
    return nil;
  }
  FBBundleDescriptor *testBundle = [FBBundleDescriptor bundleFromPath:testBundlePath error:&error];
  if (!testBundle) {
    [self.logger.error log:error.description];
    return nil;
  }
  return [[FBXCodebuildTestRunDescriptor alloc] initWithURL:xctestrunURL name:testTarget testBundle:testBundle testHostBundle:testHostBundle];
}

- (FBFuture<FBInstalledArtifact *> *)saveTestBundle:(NSURL *)testBundleURL usingSymlink:(BOOL)useSymlink skipSigningBundles:(BOOL)skipSigningBundles
{
  // Test Bundles don't always have a bundle id, so fallback to another name if it's not there.
  NSError *error = nil;
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleWithFallbackIdentifierFromPath:testBundleURL.path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  return [self saveBundle:bundle usingSymlink:useSymlink skipSigningBundles:skipSigningBundles];
}

- (FBFuture<FBInstalledArtifact *> *)saveTestRun:(NSURL *)XCTestRunURL
{
  NSError *error = nil;
  // Delete old xctestrun with the same id if it exists
  NSArray<id<FBXCTestDescriptor>> *descriptors = [self getXCTestRunDescriptorsFromURL:XCTestRunURL error:&error];
  if (!descriptors) {
    return [FBFuture futureWithError:error];
  }
  if (descriptors.count != 1) {
    return [[FBIDBError
      describeFormat:@"Expected exactly one test in the xctestrun file, got: %lu", descriptors.count]
      failFuture];
  }

  id<FBXCTestDescriptor> descriptor = descriptors[0];
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
    if (![NSFileManager.defaultManager copyItemAtURL:url toURL:[newPath URLByAppendingPathComponent:url.lastPathComponent] error:&error]) {
      return [FBFuture futureWithError:error];
    }
  }

  FBInstalledArtifact *artifact = [[FBInstalledArtifact alloc] initWithName:[descriptor testBundleID] uuid:nil path:dir];
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

  NSURL *basePath = [self prepareStoragePathWithName:IdbTestBundlesFolder target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBXCTestBundleStorage *xctest = [[FBXCTestBundleStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger relocateLibraries:YES];

  basePath = [self prepareStoragePathWithName:IdbApplicationsFolder target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBBundleStorage *application = [[FBBundleStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger relocateLibraries:NO];

  basePath = [self prepareStoragePathWithName:IdbDylibsFolder target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBFileStorage *dylib = [[FBFileStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger];

  basePath = [self prepareStoragePathWithName:IdbDsymsFolder target:target error:error];
  if (!basePath) {
    return nil;
  }
  FBFileStorage *dsym = [[FBFileStorage alloc] initWithTarget:target basePath:basePath queue:queue logger:logger];

  basePath = [self prepareStoragePathWithName:IdbFrameworksFolder target:target error:error];
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

- (BOOL)clean:(NSError **)error
{
  return [self.xctest clean:error] && [self.application clean:error] && [self.dylib clean:error] && [self.dsym clean:error] && [self.framework clean:error];
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

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  NSMutableDictionary<NSString *, NSString *> *combined = NSMutableDictionary.dictionary;
  for (NSDictionary<NSString *, NSString *> *replacementMapping in @[self.application.replacementMapping, self.dylib.replacementMapping, self.framework.replacementMapping, self.dsym.replacementMapping]) {
    [combined addEntriesFromDictionary:replacementMapping];
  }
  return combined;
}

@end
