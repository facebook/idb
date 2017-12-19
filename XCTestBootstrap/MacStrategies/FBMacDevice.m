/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBMacDevice.h"

#import <DTXConnectionServices/CDStructures.h>
#import <DTXConnectionServices/DTXSocketTransport.h>
#import <FBControlCore/FBControlCore.h>
#import <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#import "FBProductBundle.h"
#import "FBMacTestPreparationStrategy.h"
#import "FBManagedTestRunStrategy.h"
#import "XCTestBootstrapError.h"

@protocol XCTestManager_XPCControl <NSObject>
- (void)_XCT_requestConnectedSocketForTransport:(void (^)(NSFileHandle *, NSError *))arg1;
@end

@interface FBMacDevice()
@property (nonatomic, strong) NSMutableDictionary<NSString *, FBProductBundle *> *bundleIDToProductMap;
@property (nonatomic, strong) NSMutableDictionary<NSString *, FBTask *> *bundleIDToRunningTask;
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic, copy) NSString *workingDirectory;

@end

@implementation FBMacDevice

+ (NSString *)applicationInstallDirectory
{
  static dispatch_once_t onceToken;
  static NSString *_value;
  dispatch_once(&onceToken, ^{
    _value = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, YES).lastObject;
  });
  return _value;
}

+ (NSMutableDictionary<NSString *, FBProductBundle *> *)fetchInstalledApplications
{
  NSMutableDictionary<NSString *, FBProductBundle *> *mapping = @{}.mutableCopy;
  NSArray<NSString *> *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.applicationInstallDirectory error:nil];
  for (NSString *fileOrDirectory in content) {
    if (![fileOrDirectory.pathExtension isEqualToString:@"app"]) {
      continue;
    }
    NSString *path = [FBMacDevice.applicationInstallDirectory stringByAppendingPathComponent:fileOrDirectory];
    FBProductBundle *product =
    [[[FBProductBundleBuilder builder]
      withBundlePath:path]
     buildWithError:nil];
    if (product) {
      mapping[product.bundleID] = product;
    }
  }
  return mapping;
}


- (instancetype)init
{
  self = [super init];
  if (self) {
    _architecture = FBArchitectureX86_64;
    _asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    _auxillaryDirectory = NSTemporaryDirectory();
    _bundleIDToProductMap = [FBMacDevice fetchInstalledApplications];
    _bundleIDToRunningTask = @{}.mutableCopy;
    _launchdProcess = [[FBProcessInfo alloc] initWithProcessIdentifier:1 launchPath:@"/sbin/launchd" arguments:@[] environment:@{}];
    _requiresTestDaemonMediationForTestHostConnection = YES;
    _shortDescription = _name = @"Local MacOSX host";
    _udid = [FBMacDevice resolveDeviceUDID];
    _state = FBSimulatorStateBooted;
    _targetType = FBiOSTargetTypeLocalMac;
    _workQueue = dispatch_get_main_queue();
    _workingDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
  }
  return self;
}

- (instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger
{
  self = [self init];
  if (self) {
    _logger = logger;
  }
  return self;
}

- (id<FBDeviceOperator>)deviceOperator
{
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


#pragma mark - FBDeviceOperator
@synthesize requiresTestDaemonMediationForTestHostConnection = _requiresTestDaemonMediationForTestHostConnection;
@synthesize udid = _udid;

- (DTXTransport *)makeTransportForTestManagerServiceWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
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
  __block NSError *xctError;
  __block DTXSocketTransport *transport;
  [proxy _XCT_requestConnectedSocketForTransport:^(NSFileHandle *file, NSError *xctInnerError) {
    if (!file) {
      [logger logFormat:@"Error requesting connection with test manager daemon: %@", xctInnerError.description];
      xctError = xctInnerError;
      return;
    }
    transport = [[objc_lookUpClass("DTXSocketTransport") alloc] initWithConnectedSocket:file.fileDescriptor disconnectAction:^{
      [logger log:@"Disconnected from test manager daemon socket"];
      [file closeFile];
    }];
  }];
  if (error) {
    *error = xctError;
  }
  return transport;
}

- (nullable FBProductBundle *)applicationBundleWithBundleID:(nonnull NSString *)bundleID error:(NSError *__autoreleasing _Nullable * _Nullable)error
{
  FBProductBundle *bundle = self.bundleIDToProductMap[bundleID];
  if (!bundle) {
    if (error) {
      *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was installed by XCTestBootstrap", bundleID];
    }
    return nil;
  }
  return bundle;
}

- (nullable NSString *)applicationPathForApplicationWithBundleID:(nonnull NSString *)bundleID error:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  FBProductBundle *bundle = self.bundleIDToProductMap[bundleID];
  if (!bundle) {
    if (error) {
      *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was installed by XCTestBootstrap", bundleID];
    }
    return nil;
  }
  return bundle.path;
}

- (nonnull FBFuture<NSNumber *> *)processIDWithBundleID:(nonnull NSString *)bundleID
{
  FBTask *task = self.bundleIDToRunningTask[bundleID];
  if (!task) {
    NSError *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was not launched by XCTestBootstrap", bundleID];
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:@(self.bundleIDToRunningTask[bundleID].processIdentifier)];
}

- (BOOL)waitForDeviceToBecomeAvailableWithError:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  return YES;
}


#pragma mark Not supported

- (nullable FBDiagnostic *)attemptToFindCrashLogForProcess:(pid_t)pid bundleID:(nonnull NSString *)bundleID sinceDate:(nonnull NSDate *)date
{
  NSAssert(nil, @"attemptToFindCrashLogForProcess:bundleID:sinceDate: is not yet supported");
  return nil;
}

- (BOOL)cleanApplicationStateWithBundleIdentifier:(nonnull NSString *)bundleID error:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  NSAssert(nil, @"cleanApplicationStateWithBundleIdentifier:error: is not yet supported");
  return NO;
}

- (nonnull NSString *)consoleString
{
  NSAssert(nil, @"consoleString is not yet supported");
  return nil;
}

- (nonnull NSString *)containerPathForApplicationWithBundleID:(nonnull NSString *)bundleID error:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  NSAssert(nil, @"containerPathForApplicationWithBundleID:error: is not yet supported");
  return nil;
}

- (BOOL)uploadApplicationDataAtPath:(nonnull NSString *)path bundleID:(nonnull NSString *)bundleID error:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  NSAssert(nil, @"uploadApplicationDataAtPath:bundleID:error: is not yet supported");
  return NO;
}


#pragma mark - FBiOSTarget
@synthesize architecture = _architecture;
@synthesize asyncQueue = _asyncQueue;
@synthesize auxillaryDirectory = _auxillaryDirectory;
@synthesize name = _name;
@synthesize launchdProcess = _launchdProcess;
@synthesize logger = _logger;
@synthesize osVersion = _osVersion;
@synthesize shortDescription = _shortDescription;
@synthesize state = _state;
@synthesize targetType = _targetType;
@synthesize workQueue = _workQueue;

// Not used or set
@synthesize actionClasses;
@synthesize containerApplication;
@synthesize deviceType;
@synthesize diagnostics;


+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target
{
  return nil;
}

- (nonnull FBFuture<NSNull *> *)installApplicationWithPath:(nonnull NSString *)path
{
  NSError *error;
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:FBMacDevice.applicationInstallDirectory]) {
    if (![fm createDirectoryAtPath:FBMacDevice.applicationInstallDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
      return [FBFuture futureWithResult:error];
    }
  }

  NSString *dest = [FBMacDevice.applicationInstallDirectory stringByAppendingPathComponent:path.lastPathComponent];
  if ([fm fileExistsAtPath:dest]) {
    if (![fm removeItemAtPath:dest error:&error]) {
      return [FBFuture futureWithResult:error];
    }
  }
  if (![fm copyItemAtPath:path toPath:dest error:&error]) {
    return [FBFuture futureWithResult:error];
  }
  FBProductBundle *product =
  [[[FBProductBundleBuilder builder]
    withBundlePath:dest]
   buildWithError:&error];
  if (error) {
    return [FBFuture futureWithResult:error];
  }
  self.bundleIDToProductMap[product.bundleID] = product;
  return [FBFuture futureWithResult:[NSNull null]];
}

- (nonnull FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(nonnull NSString *)bundleID
{
  FBProductBundle *product = self.bundleIDToProductMap[bundleID];
  if (!product) {
    NSError *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was not installed by XCTestBootstrap", bundleID];
    return [FBFuture futureWithError:error];
  }
  NSError *error;
  if (![[NSFileManager defaultManager] removeItemAtPath:product.path error:&error]) {
    return [FBFuture futureWithResult:error];
  }
  [self.bundleIDToProductMap removeObjectForKey:bundleID];
  return [FBFuture futureWithResult:[NSNull null]];
}

- (nonnull FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSString *bundleID in self.bundleIDToProductMap) {
    FBProductBundle *productBundle = self.bundleIDToProductMap[bundleID];
    NSError *error;
    FBApplicationBundle *bundle = [FBApplicationBundle applicationWithPath:productBundle.path error:&error];
    if (!bundle) {
      return [FBFuture futureWithError:error];
    }
    [result addObject: [FBInstalledApplication installedApplicationWithBundle:bundle installType:FBApplicationInstallTypeMac]];
  }
  return [FBFuture futureWithResult:result];
}

- (nonnull FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(nonnull NSString *)bundleID
{
  return [FBFuture futureWithResult:@(self.bundleIDToProductMap[bundleID] != nil)];
}

- (nonnull FBFuture<NSNull *> *)killApplicationWithBundleID:(nonnull NSString *)bundleID
{
  FBTask *task = self.bundleIDToRunningTask[bundleID];
  if (!task) {
    NSError *error = [XCTestBootstrapError errorForFormat:@"Application with bundleID (%@) was not launched by XCTestBootstrap", bundleID];
    return [FBFuture futureWithError:error];
  }
  [task terminate];
  [self.bundleIDToRunningTask removeObjectForKey:bundleID];
  return [FBFuture futureWithResult:[NSNull null]];
}

- (nonnull FBFuture<NSNumber *> *)launchApplication:(nonnull FBApplicationLaunchConfiguration *)configuration
{
  FBProductBundle *product = self.bundleIDToProductMap[configuration.bundleID];
  if (!product) {
    return [FBFuture futureWithResult:@0];
  }
  FBTask *task = [[[[FBTaskBuilder
    withLaunchPath:product.binaryPath]
    withArguments:configuration.arguments]
    withEnvironment:configuration.environment]
    build];
  [task startAsynchronously];
  self.bundleIDToRunningTask[product.bundleID] = task;
  return [FBFuture futureWithResult:@(task.processIdentifier)];
}

- (nonnull FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(nonnull FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nonnull id<FBControlCoreLogger>)logger
{
  FBMacTestPreparationStrategy *testPreparationStrategy =
    [FBMacTestPreparationStrategy
     strategyWithTestLaunchConfiguration:testLaunchConfiguration
     workingDirectory:self.workingDirectory];
  return (FBFuture<id<FBiOSTargetContinuation>> *)
    [[FBManagedTestRunStrategy
      strategyWithTarget:self
      configuration:testLaunchConfiguration
      reporter:reporter
      logger:logger
      testPreparationStrategy:testPreparationStrategy]
    connectAndStart];
}

- (NSComparisonResult)compare:(nonnull id<FBiOSTarget>)target
{
  return NSOrderedSame; // There should be only one
}

- (NSDictionary *)jsonSerializableRepresentation
{
  return [FBiOSTargetFormat.fullFormat extractFrom:self];
}


#pragma mark Not supported

- (nullable id<FBBitmapStream>)createStreamWithConfiguration:(nonnull FBBitmapStreamConfiguration *)configuration error:(NSError *_Nullable __autoreleasing * _Nullable)error
{
  NSAssert(nil, @"createStreamWithConfiguration:configuration:error: is not yet supported");
  return nil;
}

- (nonnull FBFuture<id<FBiOSTargetContinuation>> *)startRecordingToFile:(nullable NSString *)filePath
{
  NSAssert(nil, @"startRecordingToFile: is not yet supported");
  return nil;
}

- (nonnull FBFuture<NSNull *> *)stopRecording
{
  NSAssert(nil, @"stopRecording: is not yet supported");
  return nil;
}

- (nonnull FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(nonnull NSString *)bundlePath timeout:(NSTimeInterval)timeout
{
  NSAssert(nil, @"listTestsForBundleAtPath:timeout: is not yet supported");
  return nil;
}

- (nonnull FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(nonnull NSArray<NSString *> *)arguments
{
  NSAssert(nil, @"logLinesWithArguments: is not yet supported");
  return nil;
}

- (nonnull FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(nonnull NSArray<NSString *> *)arguments consumer:(nonnull id<FBFileConsumer>)consumer
{
  NSAssert(nil, @"tailLog:consumer: is not yet supported");
  return nil;
}

@end
