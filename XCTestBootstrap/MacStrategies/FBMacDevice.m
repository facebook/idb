/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBMacDevice.h"

#import <CoreFoundation/CoreFoundation.h>
#import <FBControlCore/FBControlCore.h>
#import <IOKit/IOKitLib.h>

#import "FBManagedTestRunStrategy.h"
#import "XCTestBootstrapError.h"
#import "FBListTestStrategy.h"
#import "FBXCTestConfiguration.h"
#import "FBMacLaunchedApplication.h"

@protocol XCTestManager_XPCControl <NSObject>
- (void)_XCT_requestConnectedSocketForTransport:(void (^)(NSFileHandle *, NSError *))arg1;
@end

@interface FBMacDevice()

@property (nonatomic, strong) NSMutableDictionary<NSString *, FBBundleDescriptor *> *bundleIDToProductMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, FBProcess *> *bundleIDToRunningTask;
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic, copy) NSString *workingDirectory;
@property (nonatomic, assign, readonly) BOOL catalyst;

@end

@implementation FBMacDevice

@synthesize temporaryDirectory = _temporaryDirectory;

+ (NSString *)applicationInstallDirectory
{
  static dispatch_once_t onceToken;
  static NSString *_value;
  dispatch_once(&onceToken, ^{
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *parentDir = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, YES).lastObject;
    _value = [parentDir stringByAppendingPathComponent:uuid];
  });
  return _value;
}

+ (NSMutableDictionary<NSString *, FBBundleDescriptor *> *)fetchInstalledApplications
{
  NSMutableDictionary<NSString *, FBBundleDescriptor *> *mapping = @{}.mutableCopy;
  NSArray<NSString *> *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.applicationInstallDirectory error:nil];
  for (NSString *fileOrDirectory in content) {
    if (![fileOrDirectory.pathExtension isEqualToString:@"app"]) {
      continue;
    }
    NSString *path = [FBMacDevice.applicationInstallDirectory stringByAppendingPathComponent:fileOrDirectory];
    FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:path error:nil];
    if (bundle && bundle.identifier) {
      mapping[bundle.identifier] = bundle;
    }
  }
  return mapping;
}


- (instancetype)init
{
  self = [super init];
  if (self) {

    _architectures = [[FBArchitectureProcessAdapter hostMachineSupportedArchitectures] allObjects];
    _asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    NSString *explicitTmpDirectory = NSProcessInfo.processInfo.environment[@"IDB_MAC_AUXILLIARY_DIR"];
    if (explicitTmpDirectory) {
      _auxillaryDirectory = [[explicitTmpDirectory stringByAppendingPathComponent:@"idb-mac-aux"] stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
    } else {
      _auxillaryDirectory = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"idb-mac-cwd"] stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
    }
    _bundleIDToProductMap = [FBMacDevice fetchInstalledApplications];
    _bundleIDToRunningTask = @{}.mutableCopy;
    _udid = [FBMacDevice resolveDeviceUDID];
    _state = FBiOSTargetStateBooted;
    _targetType = FBiOSTargetTypeLocalMac;
    _workQueue = dispatch_get_main_queue();
    _temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:self.logger];
    _workingDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
    _screenInfo = nil;
    _osVersion = [FBOSVersion genericWithName:FBOSVersionNamemac];
    _name = [[NSHost currentHost] localizedName];
  }
  return self;
}

- (instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger;
{
  return [self initWithLogger:logger catalyst:NO];
}

- (instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger catalyst:(BOOL)catalyst;
{
  self = [self init];
  if (self) {
    _logger = logger;
    _catalyst = catalyst;
  }
  return self;
}

- (FBFuture<NSNull *> *)restorePrimaryDeviceState
{
  NSMutableArray<FBFuture *> *queuedFutures = @[].mutableCopy;

  NSMutableArray<FBFuture *> *killFutures = @[].mutableCopy;
  for (NSString *bundleID in self.bundleIDToRunningTask.copy) {
    [killFutures addObject:[self killApplicationWithBundleID:bundleID]];
  }
  if (killFutures.count > 0) {
    [queuedFutures addObject:[FBFuture race:killFutures]];
  }

  NSMutableArray<FBFuture *> *uninstallFutures = @[].mutableCopy;
  for (NSString *bundleID in self.bundleIDToProductMap.copy) {
    [uninstallFutures addObject:[self uninstallApplicationWithBundleID:bundleID]];
  }
  if (uninstallFutures.count > 0) {
    [queuedFutures addObject:[FBFuture race:uninstallFutures]];
  }

  if (queuedFutures.count > 0) {
    return [FBFuture futureWithFutures:queuedFutures];
  }
  return [FBFuture futureWithResult:[NSNull null]];
}

- (NSString *)runtimeRootDirectory
{
  return [self platformRootDirectory];
}

- (NSString *)platformRootDirectory
{
  return [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/MacOSX.platform"];
}

- (NSString *)xctestPath
{
  return [FBXcodeConfiguration.developerDirectory
    stringByAppendingPathComponent:@"usr/bin/xctest"];
}

- (FBFuture<NSString *> *)extendedTestShim
{
  return [[FBXCTestShimConfiguration
    sharedShimConfigurationWithLogger:self.logger]
    onQueue:self.asyncQueue map:^(FBXCTestShimConfiguration *shims) {
      return shims.macOSTestShimPath;
    }];
}

+ (NSString *)resolveDeviceUDID
{
  io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
  if (!platformExpert) {
    return nil;
  }
  CFTypeRef serialNumberAsCFString =
    IORegistryEntryCreateCFProperty(
      platformExpert,
      CFSTR(kIOPlatformSerialNumberKey),
      kCFAllocatorDefault,
      0);
  IOObjectRelease(platformExpert);
  return (NSString *)CFBridgingRelease(serialNumberAsCFString);
}

@synthesize udid = _udid;

- (FBFutureContext<NSNumber *> *)transportForTestManagerService
{
  id<FBControlCoreLogger> logger = self.logger;
  NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:@"com.apple.testmanagerd.control" options:0];
  NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(XCTestManager_XPCControl)];
  [connection setRemoteObjectInterface:interface];
  __weak __typeof__(self) weakSelf = self;
  [connection setInterruptionHandler:^{
    weakSelf.connection = nil;
    [logger log:@"Connection with test manager daemon was interrupted"];
  }];
  [connection setInvalidationHandler:^{
    weakSelf.connection = nil;
    [logger log:@"Invalidated connection with test manager daemon"];
  }];
  [connection resume];
  id<XCTestManager_XPCControl> proxy = [connection synchronousRemoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
    if (!proxyError) {
      return;
    }
    [logger logFormat:@"Error occured during synchronousRemoteObjectProxyWithErrorHandler call: %@", proxyError.description];
    weakSelf.connection = nil;
  }];

  self.connection = connection;
  __block NSError *error;
  __block NSFileHandle *transport;
  [proxy _XCT_requestConnectedSocketForTransport:^(NSFileHandle *file, NSError *xctError) {
    if (!file) {
      [logger logFormat:@"Error requesting connection with test manager daemon: %@", xctError.description];
      error = xctError;
      return;
    }
    transport = file;
  }];
  if (!transport) {
    return [FBFutureContext futureContextWithError:error];
  }
  return [[FBFuture
    futureWithResult:@(transport.fileDescriptor)]
    onQueue:self.workQueue contextualTeardown:^(id _, FBFutureState __) {
      [transport closeFile];
      return FBFuture.empty;
  }];
}

- (nonnull FBFuture<NSNumber *> *)processIDWithBundleID:(nonnull NSString *)bundleID
{
  FBProcess *task = self.bundleIDToRunningTask[bundleID];
  if (!task) {
    NSError *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was not launched by XCTestBootstrap", bundleID];
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:@(self.bundleIDToRunningTask[bundleID].processIdentifier)];
}

#pragma mark Not supported

- (nonnull NSString *)consoleString
{
  NSAssert(nil, @"consoleString is not yet supported");
  return nil;
}

#pragma mark - FBiOSTarget

@synthesize architectures = _architectures;
@synthesize asyncQueue = _asyncQueue;
@synthesize auxillaryDirectory = _auxillaryDirectory;
@synthesize name = _name;
@synthesize logger = _logger;
@synthesize osVersion = _osVersion;
@synthesize state = _state;
@synthesize targetType = _targetType;
@synthesize workQueue = _workQueue;
@synthesize screenInfo = _screenInfo;

// Not used or set
@synthesize deviceType;

- (BOOL) requiresBundlesToBeSigned {
  return NO;
}

+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target
{
  NSAssert(nil, @"commandsWithTarget is not yet supported");
  return nil;
}

- (FBFuture<FBInstalledApplication *> *)installApplicationWithPath:(NSString *)path
{
  NSError *error;
  FBBundleDescriptor *bundle = [FBBundleDescriptor bundleFromPath:path error:&error];
  if (error) {
    return [FBFuture futureWithError:error];
  }
  self.bundleIDToProductMap[bundle.identifier] = bundle;
  return [FBFuture futureWithResult:[FBInstalledApplication installedApplicationWithBundle:bundle installType:FBApplicationInstallTypeUnknown dataContainer:nil]];
}

- (nonnull FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(nonnull NSString *)bundleID
{
  FBBundleDescriptor *bundle = self.bundleIDToProductMap[bundleID];
  if (!bundle) {
    return [[XCTestBootstrapError
      describeFormat:@"Application with bundleID (%@) was not installed by XCTestBootstrap", bundleID]
      failFuture];
  }

  if (![[NSFileManager defaultManager] fileExistsAtPath:bundle.path]) {
    return [FBFuture futureWithResult:[NSNull null]];
  }

  NSError *error;
  if (![[NSFileManager defaultManager] removeItemAtPath:bundle.path error:&error]) {
    return [FBFuture futureWithError:error];
  }
  [self.bundleIDToProductMap removeObjectForKey:bundleID];
  return [FBFuture futureWithResult:[NSNull null]];
}

- (nonnull FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSString *bundleID in self.bundleIDToProductMap) {
    FBBundleDescriptor *bundle = self.bundleIDToProductMap[bundleID];
    NSError *error;
    bundle = [FBBundleDescriptor bundleFromPath:bundle.path error:&error];
    if (!bundle) {
      return [FBFuture futureWithError:error];
    }
    [result addObject:[FBInstalledApplication installedApplicationWithBundle:bundle installType:FBApplicationInstallTypeMac dataContainer:nil]];
  }
  return [FBFuture futureWithResult:result];
}

- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID
{
  FBBundleDescriptor *bundle = self.bundleIDToProductMap[bundleID];
  NSError *error;
  bundle = [FBBundleDescriptor bundleFromPath:bundle.path error:&error];
  if (!bundle) {
    return [FBFuture futureWithError:error];
  }
  FBInstalledApplication *installedApp = [FBInstalledApplication installedApplicationWithBundle:bundle installType:FBApplicationInstallTypeMac dataContainer:nil];
  return [FBFuture futureWithResult:installedApp];
}

- (nonnull FBFuture<NSNull *> *)killApplicationWithBundleID:(nonnull NSString *)bundleID
{
  FBProcess *task = self.bundleIDToRunningTask[bundleID];
  if (!task) {
    NSError *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was not launched by XCTestBootstrap", bundleID];
    return [FBFuture futureWithError:error];
  }
  [task sendSignal:SIGTERM backingOffToKillWithTimeout:2 logger:self.logger];
  [self.bundleIDToRunningTask removeObjectForKey:bundleID];
  return [FBFuture futureWithResult:[NSNull null]];
}

- (FBFuture<FBMacLaunchedApplication *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  FBBundleDescriptor *bundle = self.bundleIDToProductMap[configuration.bundleID];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Could not find application for %@", configuration.bundleID]
      failFuture];
  }
  return [[[[[FBProcessBuilder
    withLaunchPath:bundle.binary.path]
    withArguments:configuration.arguments]
    withEnvironment:configuration.environment]
    start]
    onQueue:self.workQueue map:^ FBMacLaunchedApplication* (FBProcess *task) {
      self.bundleIDToRunningTask[bundle.identifier] = task;
      return [[FBMacLaunchedApplication alloc]
       initWithBundleID:bundle.identifier
       processIdentifier:task.processIdentifier
       device:self
       queue:self.workQueue];
  }];
}

- (nonnull FBFuture<NSDictionary<NSString *,FBProcessInfo *> *> *)runningApplications
{
  NSMutableDictionary<NSString *, FBProcessInfo *> *runningProcesses = @{}.mutableCopy;
  FBProcessFetcher *fetcher = [FBProcessFetcher new];
  for (NSString *bundleId in self.bundleIDToRunningTask.allKeys) {
    FBProcess *task = self.bundleIDToRunningTask[bundleId];
    runningProcesses[bundleId] = [fetcher processInfoFor:task.processIdentifier];
  }
  return [FBFuture futureWithResult:runningProcesses];
}

- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(nonnull FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(nonnull id<FBControlCoreLogger>)logger
{
    return [FBManagedTestRunStrategy
      runToCompletionWithTarget:self
      configuration:testLaunchConfiguration
      codesign:nil
      workingDirectory:self.workingDirectory
      reporter:reporter
      logger:logger];
}

- (NSString *)uniqueIdentifier
{
  return self.udid;
}

- (NSDictionary<NSString *, id> *)extendedInformation
{
  return @{};
}

- (NSComparisonResult)compare:(nonnull id<FBiOSTarget>)target
{
  return NSOrderedSame; // There should be only one
}

- (NSString *)customDeviceSetPath
{
  return nil;
}

- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state
{
  return FBiOSTargetResolveState(self, state);
}

- (FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state
{
  return FBiOSTargetResolveLeavesState(self, state);
}

- (NSDictionary<NSString *, NSString *> *)replacementMapping
{
  return NSDictionary.dictionary;
}

- (NSDictionary<NSString *, NSString *> *)environmentAdditions
{
  if (self.catalyst) {
    return @{@"DYLD_FORCE_PLATFORM" : @"6"};
  }
  else {
    return NSDictionary.dictionary;
  }
}


#pragma mark Not supported

- (FBFuture<id<FBVideoStream>> *)createStreamWithConfiguration:(FBVideoStreamConfiguration *)configuration
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<id<FBiOSTargetOperation>> *)startRecordingToFile:(NSString *)filePath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(NSString *)appPath
{
  NSError *error = nil;
  FBBundleDescriptor *bundleDescriptor = [FBBundleDescriptor bundleWithFallbackIdentifierFromPath:bundlePath error:&error];
  if (!bundleDescriptor) {
    return [FBFuture futureWithError:error];
  }

  FBListTestConfiguration *configuration = [FBListTestConfiguration
    configurationWithEnvironment:@{}
    workingDirectory:self.auxillaryDirectory
    testBundlePath:bundlePath
    runnerAppPath:appPath
    waitForDebugger:NO
    timeout:timeout
    architectures:bundleDescriptor.binary.architectures];

  return [[[FBListTestStrategy alloc]
    initWithTarget:self
    configuration:configuration
    logger:self.logger]
    listTests];
}

- (FBFuture<id<FBiOSTargetOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate
{
  return [FBCrashLogNotifier.sharedInstance nextCrashLogForPredicate:predicate];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate useCache:(BOOL)useCache
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)pruneCrashes:(NSPredicate *)predicate
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFutureContext<id<FBFileContainer>> *)crashLogFiles
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFuture<FBInstrumentsOperation *> *)startInstruments:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<FBXCTraceRecordOperation *> *)startXctraceRecord:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<FBProcess *> *)launchProcess:(FBProcessSpawnConfiguration *)configuration
{
  return [FBProcess launchProcessWithConfiguration:configuration logger:self.logger];
}

@end
