/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBCommandExecutor.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBIDBStorageManager.h"
#import "FBIDBError.h"
#import "FBIDBPortsConfiguration.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"

@interface FBIDBCommandExecutor ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBIDBPortsConfiguration *ports;

@end

@implementation FBIDBCommandExecutor

#pragma mark Initializers


+ (instancetype)commandExecutorForTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory ports:(FBIDBPortsConfiguration *)ports logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithTarget:target storageManager:storageManager temporaryDirectory:temporaryDirectory ports:ports logger:[logger withName:@"grpc_handler"]];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory ports:(FBIDBPortsConfiguration *)ports logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _storageManager = storageManager;
  _temporaryDirectory = temporaryDirectory;
  _ports = ports;
  _logger = logger;
  _logManager = [FBDeltaUpdateManager logManagerWithTarget:target];
  _instrumentsManager = [FBDeltaUpdateManager instrumentsManagerWithTarget:target];
  _testManager = [FBDeltaUpdateManager xctestManagerWithTarget:self.target bundleStorage:storageManager.xctest temporaryDirectory:temporaryDirectory];
  _videoManager = [FBDeltaUpdateManager videoManagerForTarget:self.target];

  return self;
}

#pragma mark Installation

- (FBFuture<NSDictionary<FBInstalledApplication *, id> *> *)list_apps
{
  return [[FBFuture
    futureWithFutures:@[
      [self.target installedApplications],
      [self.target runningApplications],
    ]]
    onQueue:self.target.workQueue map:^(NSArray<id> *results) {
      NSArray<FBInstalledApplication *> *installed = results[0];
      NSDictionary<NSString *, NSNumber *> *running = results[1];
      NSMutableDictionary<FBInstalledApplication *, id> *listing = NSMutableDictionary.dictionary;
      for (FBInstalledApplication *application in installed) {
        listing[application] = running[application.bundle.identifier] ?: NSNull.null;
      }
      return listing;
    }];
}

- (FBFuture<NSString *> *)install:(nullable NSData *)appData filePath:(nullable NSString *)filePath
{
  if (filePath) {
    return [self install_file_path:filePath];
  }
  if (appData) {
    return [self install_binary:appData];
  }
  return [[FBIDBError
    describeFormat:@"no filepath or data found for install"]
    failFuture];
}

- (FBFuture<NSString *> *)install_file_path:(NSString *)filePath
{
  return [self installExtractedApplication:[FBApplicationBundle onQueue:self.target.asyncQueue findOrExtractApplicationAtPath:filePath logger:self.logger]];
}

- (FBFuture<NSString *> *)install_binary:(NSData *)data
{
  FBFutureContext<FBApplicationBundle *> *bundle = [[self.temporaryDirectory
    withArchiveExtracted:data]
    onQueue:self.target.asyncQueue pend:^(NSURL *tempDirectory) {
      return [FBApplicationBundle findAppPathFromDirectory:tempDirectory];
    }];
  return [self installExtractedApplication:bundle];
}

- (FBFuture<NSString *> *)install_stream:(FBProcessInput *)input
{
  return [self installExtractedApplication:[FBApplicationBundle onQueue:self.target.asyncQueue extractApplicationFromInput:input logger:self.logger]];
}

- (FBFuture<NSString *> *)xctest_install_file_path:(NSString *)filePath
{
  return [self installXctestFilePath:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]]];
}

- (FBFuture<NSString *> *)xctest_install_stream:(FBProcessInput *)stream
{
  return [self installXctest:[self.temporaryDirectory withArchiveExtractedFromStream:stream]];
}

- (FBFuture<NSString *> *)xctest_install_binary:(NSData *)tarData
{
  return [self installXctest:[self.temporaryDirectory withArchiveExtracted:tarData]];
}

- (FBFuture<NSString *> *)install_dylib_file_path:(NSString *)filePath
{
  return [self installFile:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.dylib];
}

- (FBFuture<NSString *> *)install_dylib_stream:(FBProcessInput *)input name:(NSString *)name
{
  return [self installFile:[self.temporaryDirectory withGzipExtractedFromStream:input name:name] intoStorage:self.storageManager.dylib];
}

- (FBFuture<NSString *> *)install_framework_file_path:(NSString *)filePath
{
  return [self installBundle:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.framework];
}

- (FBFuture<NSString *> *)install_framework_stream:(FBProcessInput *)input
{
  return [self installBundle:[self.temporaryDirectory withArchiveExtractedFromStream:input] intoStorage:self.storageManager.framework];
}

- (FBFuture<NSString *> *)install_dsym_file_path:(NSString *)filePath
{
  return [self installBundle:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.dsym];
}

- (FBFuture<NSString *> *)install_dsym_stream:(FBProcessInput *)input
{
  return [self installBundle:[self.temporaryDirectory withArchiveExtractedFromStream:input] intoStorage:self.storageManager.dsym];
}

#pragma mark Public Methods

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [[self
    screenshotCommands]
    onQueue:self.target.workQueue fmap:^(id<FBScreenshotCommands> commands) {
        return [commands takeScreenshot:format];
    }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath inContainerOfApplication:(NSString *)bundleID
{
  return [[self
    targetDataCommands]
    onQueue:self.target.workQueue fmap:^(id<FBApplicationDataCommands> targetApplicationData) {
      return [targetApplicationData createDirectory:directoryPath inContainerOfApplication:bundleID];
    }];
}

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityInfoAtPoint:(nullable NSValue *)value
{
  return [[[self
    connectToSimulatorConnection]
    onQueue:self.target.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToBridge];
    }]
    onQueue:self.target.workQueue fmap:^ FBFuture * (FBSimulatorBridge *bridge) {
      if (value) {
        return [bridge accessibilityElementAtPoint:value.pointValue];
      } else {
        return [bridge accessibilityElements];
      }
  }];
}

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityInfo
{
  return [self accessibilityInfoAtPoint:nil];
}

- (FBFuture<NSNull *> *)addMediaFromTar:(nullable NSData *)tarData orFilePath:(nullable NSArray<NSString *> *)filePaths
{
  return [[self.temporaryDirectory
    withFilesInTar:tarData orFilePaths:filePaths]
    onQueue:self.target.workQueue pop:^(NSArray<NSURL *> *mediaFileURLs) {
      return [self addMedia:mediaFileURLs];
    }];
}

- (FBFuture<NSNull *> *)addMedia:(NSArray<NSURL *> *)filePaths
{
  return [self.mediaCommands
    onQueue:self.target.asyncQueue fmap:^FBFuture *(id<FBSimulatorMediaCommands> commands) {
      return [commands addMedia:filePaths];
    }];
}

- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  return [self.targetDataCommands
    onQueue:self.target.workQueue fmap:^(id<FBApplicationDataCommands> commands) {
      return [commands movePaths:originPaths toPath:destinationPath inContainerOfApplication:bundleID];
    }];
}

- (FBFuture<NSNull *> *)pushFileFromTar:(NSData *)tarData toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  return [[self.temporaryDirectory
    withArchiveExtracted:tarData]
    onQueue:self.target.workQueue pop:^FBFuture *(NSURL *extractionDirectory) {
      NSError *error;
      NSArray<NSURL *> *paths = [NSFileManager.defaultManager contentsOfDirectoryAtURL:extractionDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
      if (!paths) {
        return [FBFuture futureWithError:error];
      }
      return [self pushFiles:paths toPath:destinationPath inContainerOfApplication:bundleID];
   }];
}

- (FBFuture<NSNull *> *)pushFiles:(NSArray<NSURL *> *)paths toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  return [FBFuture
    onQueue:self.target.asyncQueue resolve:^FBFuture<NSNull *> *{
      return [[self targetDataCommands]
        onQueue:self.target.workQueue fmap:^FBFuture *(id<FBApplicationDataCommands> targetApplicationsData) {
          return [targetApplicationsData copyItemsAtURLs:paths toContainerPath:destinationPath inBundleID:bundleID];
        }];
  }];
}

- (FBFuture<NSString *> *)pullFilePath:(NSString *)path inContainerOfApplication:(NSString *)bundleID destinationPath:(NSString *)destinationPath
{
  return [[self.targetDataCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBApplicationDataCommands> commands) {
      return [commands copyDataFromContainerOfApplication:bundleID atContainerPath:path toDestinationPath:destinationPath];
    }]
    fmapReplace:[FBFuture futureWithResult:destinationPath]];
}

- (FBFuture<NSData *> *)pullFile:(NSString *)path inContainerOfApplication:(NSString *)bundleID
{
  __block NSString *tempPath;

  return [[[[self.temporaryDirectory
    withTemporaryDirectory]
    onQueue:self.target.workQueue pend:^(NSURL *url) {
      tempPath = [url.path stringByAppendingPathComponent:path.lastPathComponent];
      return self.targetDataCommands;
    }]
    onQueue:self.target.workQueue pend:^(id<FBApplicationDataCommands> commands) {
     return [commands copyDataFromContainerOfApplication:bundleID atContainerPath:path toDestinationPath:tempPath];
    }]
    onQueue:self.target.workQueue pop:^(id _) {
      return [FBArchiveOperations createGzippedTarDataForPath:tempPath queue:self.target.workQueue logger:self.target.logger];
    }];
}

- (FBFuture<NSNull *> *)hid:(FBSimulatorHIDEvent *)event
{
  return [self.connectToHID
    onQueue:self.target.workQueue fmap:^FBFuture *(FBSimulatorHID *hid) {
      return [event performOnHID:hid];
    }];
}

- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths inContainerOfApplication:(NSString *)bundleID
{
  return [self.targetDataCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBApplicationDataCommands> commands) {
      return [commands removePaths:paths inContainerOfApplication:bundleID];
    }];
}

- (FBFuture<NSArray<NSString *> *> *)listPath:(NSString *)path inContainerOfApplication:(NSString *)bundleID
{
  return [self.targetDataCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBApplicationDataCommands> commands) {
      return [commands contentsOfDirectory:path inContainerOfApplication:bundleID];
    }];
}

- (FBFuture<NSNull *> *)setLocation:(double)latitude longitude:(double)longitude
{
  return [self.connectToSimulatorBridge
    onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> *(FBSimulatorBridge *bridge) {
      return [bridge setLocationWithLatitude:latitude longitude:longitude];
    }];
}

- (FBFuture<NSNull *> *)clearKeychain
{
  return [self.keychainCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorKeychainCommands> commands) {
      return [commands clearKeychain];
    }];
}

- (FBFuture<NSNull *> *)approve:(NSSet<FBSettingsApprovalService> *)services forApplication:(NSString *)bundleID
{
  return [self.settingsCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
      return [commands grantAccess:[NSSet setWithObject:bundleID] toServices:services];
    }];
}

- (FBFuture<NSNull *> *)openUrl:(NSString *)url
{
  return [self.lifecycleCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorLifecycleCommands> commands) {
      return [commands openURL:[NSURL URLWithString:url]];
    }];
}

- (FBFuture<NSNull *> *)focus
{
  return [self.lifecycleCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorLifecycleCommands> commands) {
      return [commands focus];
    }];
}

- (FBFuture<NSNull *> *)updateContacts:(NSData *)dbTarData
{
  return [[self.temporaryDirectory
    withArchiveExtracted:dbTarData]
    onQueue:self.target.workQueue pop:^(NSURL *tempDirectory) {
      return [self.settingsCommands onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
        return [commands updateContacts:tempDirectory.path];
      }];
    }];
}

- (FBFuture<NSSet<id<FBXCTestDescriptor>> *> *)listXctests
{
  return [FBFuture onQueue:self.target.workQueue resolve:^{
    NSError *error;
    NSSet<id<FBXCTestDescriptor>> *testDescriptors = [self.storageManager.xctest listTestDescriptorsWithError:&error];
    if (testDescriptors == nil) {
      return [FBFuture futureWithError:error];
    }
    return [FBFuture futureWithResult:testDescriptors];
  }];
}

static const NSTimeInterval ListTestBundleTimeout = 60.0;

- (FBFuture<NSArray<NSString *> *> *)listTestsInBundle:(NSString *)bundleID
{
  return [FBFuture onQueue:self.target.workQueue resolve:^ FBFuture<NSArray<NSString *> *> * {
    NSError *error = nil;
    id<FBXCTestDescriptor> testDescriptor = [self.storageManager.xctest testDescriptorWithID:bundleID error:&error];
    if (!testDescriptor) {
      return [FBFuture futureWithError:error];
    }
    return [self.target listTestsForBundleAtPath:testDescriptor.url.path timeout:ListTestBundleTimeout];
  }];
}

- (FBFuture<NSNull *> *)uninstallApplication:(NSString *)bundleID
{
  return [self.target uninstallApplicationWithBundleID:bundleID];
}

- (FBFuture<NSNull *> *)killApplication:(NSString *)bundleID
{
  return [self.target killApplicationWithBundleID:bundleID];
}

- (FBFuture<NSNull *> *)startVideoRecording
{
  return [[self.videoManager
    startSession:NSNull.null]
    mapReplace:NSNull.null];
}

- (FBFuture<NSData *> *)stopVideoRecording
{
  return [[self.videoManager
    sessionWithIdentifier:nil]
    onQueue:self.target.workQueue fmap:^(FBDeltaUpdateSession<NSString *> *session) {
      return [[session
        terminate]
        onQueue:self.target.workQueue map:^(NSString *videoFilePath) {
          return [NSData dataWithContentsOfFile:videoFilePath];
        }];
    }];
}

- (FBFuture<id<FBLaunchedProcess>> *)launch_app:(FBApplicationLaunchConfiguration *)configuration
{
  return [self.target launchApplication:[configuration withEnvironment:[self.storageManager interpolateEnvironmentReplacements:configuration.environment]]];
}

- (FBFuture<FBDeltaUpdateSession<FBXCTestDelta *> *> *)xctest_run:(id<FBXCTestRunRequest>)request
{
  return [self.testManager startSession:request];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_start:(NSString *)bundleID
{
  return [[self
    debugserver_prepare:bundleID]
    onQueue:self.target.workQueue fmap:^(FBApplicationBundle *application) {
      return [self.target launchDebugServerForHostApplication:application port:self.ports.debugserverPort];
    }];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_status
{
  return [FBFuture
    onQueue:self.target.workQueue resolve:^{
      id<FBDebugServer> debugServer = self.debugServer;
      if (!debugServer) {
        return [[FBControlCoreError
          describe:@"No debug server running"]
          failFuture];
      }
      return [FBFuture futureWithResult:debugServer];
    }];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_stop
{
  return [[[self
    debugserver_status]
    onQueue:self.target.workQueue fmap:^(id<FBDebugServer> debugServer) {
      return [[self.debugServer.completed cancel] mapReplace:debugServer];
    }]
    onQueue:self.target.workQueue doOnResolved:^(id _) {
      self.debugServer = nil;
    }];
}

#pragma mark Private Methods

- (FBFuture<id<FBApplicationDataCommands>> *)targetDataCommands
{
  if (![self.target conformsToProtocol:@protocol(FBApplicationDataCommands)]) {
    return [[FBControlCoreError
      describe:@"Target doesn't conform to FBApplicationDataCommands protocol"]
      failFuture];
  }
  return [FBFuture futureWithResult:self.target];
}


- (FBFuture<id<FBScreenshotCommands>> *)screenshotCommands
{
  id<FBScreenshotCommands> commands = (id<FBScreenshotCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBScreenshotCommands)]) {
    return [[FBIDBError
             describeFormat:@"Target doesn't conform to FBScreenshotCommands protocol %@", self.target]
            failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorLifecycleCommands>> *)lifecycleCommands
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorLifecycleCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorMediaCommands>> *)mediaCommands
{
  id<FBSimulatorMediaCommands> commands = (id<FBSimulatorMediaCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorMediaCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorMediaCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorKeychainCommands>> *)keychainCommands
{
  id<FBSimulatorKeychainCommands> commands = (id<FBSimulatorKeychainCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorKeychainCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorKeychainCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorSettingsCommands>> *)settingsCommands
{
  id<FBSimulatorSettingsCommands> commands = (id<FBSimulatorSettingsCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorSettingsCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorSettingsCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<FBSimulatorConnection *> *)connectToSimulatorConnection
{
  return [[self lifecycleCommands]
    onQueue:self.target.workQueue fmap:^ FBFuture<FBSimulatorConnection *> * (id<FBSimulatorLifecycleCommands> commands) {
      NSError *error = nil;
      if (![FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworks:self.target.logger error:&error]) {
        return [[FBIDBError
          describeFormat:@"SimulatorKit is required for HID interactions: %@", error]
          failFuture];
      }
      return [commands connect];
    }];
}

- (FBFuture<FBSimulatorBridge *> *)connectToSimulatorBridge
{
  return [[self
    connectToSimulatorConnection]
    onQueue:self.target.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToBridge];
    }];
}

- (FBFuture<FBSimulatorHID *> *)connectToHID
{
  return [[self
    connectToSimulatorConnection]
    onQueue:self.target.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToHID];
    }];
}

- (FBFuture<NSString *> *)installExtractedApplication:(FBFutureContext<FBApplicationBundle *> *)extractedApplication
{
  return [[extractedApplication
    onQueue:self.target.workQueue pend:^(FBApplicationBundle *appBundle){
      if (!appBundle) {
        return [FBFuture futureWithError:[FBControlCoreError errorForDescription:@"No app bundle could be extracted"]];
      }
      NSError *error = nil;
      if (![self.storageManager.application checkArchitecture:appBundle error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [[self.target installApplicationWithPath:appBundle.path] mapReplace:appBundle];
    }]
    onQueue:self.target.workQueue pop:^(FBApplicationBundle *appBundle){
      [self.logger logFormat:@"Persisting application bundle %@", appBundle];
      NSError *error = nil;
      if ([self.storageManager.application saveBundle:appBundle error:&error]) {
        [self.logger logFormat:@"Persisted application bundle %@", appBundle];
      } else {
        [self.logger logFormat:@"Failed to persist application %@", error];
      }
      return [FBFuture futureWithResult:appBundle.identifier];
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_list:(NSPredicate *)predicate
{
  return [[self.target
    crashes:predicate useCache:NO]
    onQueue:self.target.asyncQueue map:^(NSArray<FBCrashLogInfo *> *crashes) {
      return crashes;
    }];
}

- (FBFuture<FBCrashLog *> *)crash_show:(NSPredicate *)predicate
{
  return [[self.target
    crashes:predicate useCache:YES]
    onQueue:self.target.asyncQueue fmap:^(NSArray<FBCrashLogInfo *> *crashes) {
      if (crashes.count > 1) {
         return [[FBIDBError
          describeFormat:@"More than one crash log matching %@", predicate]
          failFuture];
      }
      if (crashes.count == 0) {
        return [[FBIDBError
          describeFormat:@"No crashes matching %@", predicate]
          failFuture];
      }
      FBCrashLogInfo *info = crashes.firstObject;
      NSError *error = nil;
      NSString *contents = [NSString stringWithContentsOfFile:info.crashPath encoding:NSUTF8StringEncoding error:&error];
      if (!contents) {
        return [[[FBIDBError
          describeFormat:@"Failed to read crash log for %@", info]
          causedBy:error]
          failFuture];
      }
      FBCrashLog *crash = [FBCrashLog fromInfo:info contents:contents];
      return [FBFuture futureWithResult:crash];
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_delete:(NSPredicate *)predicate
{
  return [[self.target
    pruneCrashes:predicate]
    onQueue:self.target.asyncQueue map:^(NSArray<FBCrashLogInfo *> *crashes) {
      return crashes;
    }];
}

- (FBFuture<NSString *> *)installXctest:(FBFutureContext<NSURL *> *)extractedXctest
{
  return [extractedXctest
    onQueue:self.target.workQueue pop:^(NSURL *extractionDirectory) {
    NSError *error = nil;
    NSString *testBundleID = [self.storageManager.xctest saveBundleOrTestRunFromBaseDirectory:extractionDirectory error:&error];
    if (!testBundleID) {
      return [FBFuture futureWithError:error];
    }
    return [FBFuture futureWithResult:testBundleID];
  }];
}

- (FBFuture<NSString *> *)installXctestFilePath:(FBFutureContext<NSURL *> *)bundle
{
  return [bundle
    onQueue:self.target.workQueue pop:^(NSURL *xctestURL) {
      NSError *error = nil;
      NSString *testBundleID = [self.storageManager.xctest saveBundleOrTestRun:xctestURL error:&error];
      if (!testBundleID) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:testBundleID];
    }];
}

- (FBFuture<NSString *> *)installFile:(FBFutureContext<NSURL *> *)extractedFileContext intoStorage:(FBFileStorage *)storage
{
  return [extractedFileContext
    onQueue:self.target.workQueue pop:^(NSURL *extractedFile) {
      NSError *error = nil;
      NSString *dsymPath = [storage saveFile:extractedFile error:&error];
      if (!dsymPath) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:dsymPath];
    }];
}

- (FBFuture<NSString *> *)installBundle:(FBFutureContext<NSURL *> *)extractedDirectoryContext intoStorage:(FBBundleStorage *)storage
{
  return [extractedDirectoryContext
    onQueue:self.target.workQueue pop:^(NSURL *extractedDirectory) {
      NSError *error = nil;
      FBBundleDescriptor *bundle = [FBStorageUtils bundleInDirectory:extractedDirectory error:&error];
      if (!bundle) {
        return [FBFuture futureWithError:error];
      }
      NSString *dsymPath = [storage saveBundle:bundle error:&error];
      if (!dsymPath) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:dsymPath];
    }];
}

- (FBFuture<FBApplicationBundle *> *)debugserver_prepare:(NSString *)bundleID
{
  return [FBFuture
    onQueue:self.target.workQueue resolve:^ FBFuture<FBApplicationBundle *> * {
      if (self.debugServer) {
        return [[FBControlCoreError
          describeFormat:@"Debug server is already running"]
          failFuture];
      }
      NSDictionary<NSString *, FBApplicationBundle *> *persisted = self.storageManager.application.persistedApplications;
      FBApplicationBundle *bundle = persisted[bundleID];
      if (!bundle) {
        return [[FBIDBError
          describeFormat:@"%@ not persisted application and is therefore not debuggable. Suitable applications: %@", bundleID, [FBCollectionInformation oneLineDescriptionFromArray:persisted.allKeys]]
          failFuture];
      }

      return [FBFuture futureWithResult:bundle];
  }];
}

@end
