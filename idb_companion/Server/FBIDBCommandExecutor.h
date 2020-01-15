/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBDeltaUpdateManager+XCTest.h"
#import "FBXCTestDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@class FBBundleStorageManager;
@class FBIDBLogger;
@class FBIDBPortsConfiguration;
@class FBIDBStorageManager;
@class FBInstalledArtifact;
@class FBTemporaryDirectory;

@interface FBIDBCommandExecutor : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to run against.
 @param storageManager storage for all bundles
 @param temporaryDirectory the temporary directory to use.
 @param ports the ports to use.
 @param logger a logger to log to.
 @return a new FBIDBCommandExecutor instance
 */
+ (instancetype)commandExecutorForTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory ports:(FBIDBPortsConfiguration *)ports logger:(FBIDBLogger *)logger;

#pragma mark Properties

/**
 For storage of all bundles
 */
@property (nonatomic, strong, readonly) FBIDBStorageManager *storageManager;

/**
 The xctest manager
 */
@property (nonatomic, strong, readonly) FBXCTestDeltaUpdateManager *testManager;

/**
 The running debugserver
 */
@property (nonatomic, strong, nullable, readwrite) id<FBDebugServer> debugServer;

/**
 The Temporary Directory
 */
@property (nonatomic, strong, readonly) FBTemporaryDirectory *temporaryDirectory;

#pragma mark Public Methods

/**
 Lists Apps.

 @return A future that resolves with the list of installed applications, mapped to NSNull | NSNumber of the running pid.
 */
- (FBFuture<NSDictionary<FBInstalledApplication *, id> *> *)list_apps;

/**
 Deprecated.
 Install an App via a File Path or NSData

 @param appData tar or zip app data.
 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<NSString *> *)install:(nullable NSData *)appData filePath:(nullable NSString *)filePath;

/**
 Install an App via a File Path.

 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<FBInstalledArtifact *> *)install_app_file_path:(NSString *)filePath;

/**
 Install an App via a Data stream.

 @param input the input to pipe.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<FBInstalledArtifact *> *)install_app_stream:(FBProcessInput *)input;

/**
 Deprecated.
 Install an App via a Data.

 @param appData tar or zip app data.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<FBInstalledArtifact *> *)install_app_binary:(NSData *)appData;

/**
 Installs an xctest bundle by file path.

 @param filePath the local file path of the xctest bundle
 @return a Future that resolves with the xctest identifier.
 */
- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_file_path:(NSString *)filePath;

/**
 Installs an xctest bundle by a stream of tar data

 @param input a tar stream of the xctest data.
 @return a Future that resolves with the xctest identifier.
 */
- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_stream:(FBProcessInput *)input;

/**
 Deprecated.
 Installs an xctest bundle by a tar blob

 @param tarData a tar blob of the xctest data.
 @return a Future that resolves with the xctest identifier.
 */
- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_binary:(NSData *)tarData;

/**
 Installs a dylib from a file path.

 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dylib_file_path:(NSString *)filePath;

/**
 Installs a dylib from a tar stream.

 @param input the input to pipe.
 @param name the name of the dylib
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dylib_stream:(FBProcessInput *)input name:(NSString *)name;

/**
 Installs a framework from a file path.

 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_framework_file_path:(NSString *)filePath;

/**
 Installs a dylib from a tar stream.

 @param input the input to pipe.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_framework_stream:(FBProcessInput *)input;

/**
 Installs a dSYM from a file path.

 @param input the input to pipe.
 @return A future that resolves with the dSYM Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dsym_file_path:(NSString *)filePath;

/**
 Installs dSYM(s) from a zip stream.

 @param input the input to pipe.
 @return A future that resolves with the directory containing the dSYM(s)
 */
- (FBFuture<FBInstalledArtifact *> *)install_dsym_stream:(FBProcessInput *)input;

/**
 Takes a Screenshot

 @param format the format of the data.
 @return A Future, wrapping Data of the provided format.
 */
- (FBFuture<NSData *> *)take_screenshot:(FBScreenshotFormat)format;

/**
 Creates a directory

 @param directoryPath the path of the directory.
 @param bundleID the bundle id of the app.
 @return A Future that resolves when the directory is created.
 */
- (FBFuture<NSNull *> *)create_directory:(NSString *)directoryPath in_container_of_application:(NSString *)bundleID;

/**
 Returns the accessibility info of a point on the screen

 @param point location on the screen (NSValue<NSPoint> *), returns info for the whole screen if nil
 @return A Future that resolves with the accessibility info
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibility_info_at_point:(nullable NSValue *)point;


/**
 Returns the accessibility info of the entire screen

 @return A Future that resolves with the accessibility info
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibility_info;

/**
 Adds all the media files (photos, videos, ...) contained in the tar or specified by the files paths to the target
 Exactly one of tarData or filePaths must be provided

 @param tarData a tar containing media files
 @param filePaths local file paths to the media files
 @return A Future that resolves when complete
 */
- (FBFuture<NSNull *> *)add_media_from_tar:(nullable NSData *)tarData or_file_path:(nullable NSArray<NSString *> *)filePaths;

/**
 Adds media files (photos, videos, ...) to the target

 @param filePaths local file paths to the media files
 @return A Future that resolves when complete
 */
- (FBFuture<NSNull *> *)add_media:(NSArray<NSURL *> *)filePaths;

/**
 Move data within the container to a different path

 @param originPaths relative paths to the container where data resides
 @param destinationPath relative path where the data will be moved to
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)move_paths:(NSArray<NSString *> *)originPaths to_path:(NSString *)destinationPath in_container_of_application:(NSString *)bundleID;

/**
 Push files to an applications container from a tar

 @param tarData file content
 @param destinationPath relative path to the container where the file will reside
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)push_file_from_tar:(NSData *)tarData to_path:(NSString *)destinationPath in_container_of_application:(NSString *)bundleID;

/**
 Push files to an applications container

 @param paths Paths of the files to push
 @param destinationPath relative path to the container where the file will reside
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)push_files:(NSArray<NSURL *> *)paths to_path:(NSString *)destinationPath in_container_of_application:(NSString *)bundleID;

/**
 Pull a file from an applications container

 @param path relative path to the container where file resides
 @param bundleID the Bundle Identifier of the Container.
 @param destinationPath path to write the file to.
 @return A future that resolves the path the file is copied to.
 */
- (FBFuture<NSString *> *)pull_file_path:(NSString *)path in_container_of_application:(NSString *)bundleID destination_path:(nullable NSString *)destinationPath;

/**
 Pull a file from an applications container

 @param path relative path to the container where file resides
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves the content of that file.
 */
- (FBFuture<NSData *> *)pull_file:(NSString *)path in_container_of_application:(NSString *)bundleID;

/**
 Remove path within the container

 @param paths relative paths to the container where data resides
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)remove_paths:(NSArray<NSString *> *)paths in_container_of_application:(NSString *)bundleID;

/**
 Lists path within the container

 @param path relative path to the container where data resides
 @param bundleID the Bundle Identifier of the Container.
 @return A future that resolves with the list of files.
 */
- (FBFuture<NSArray<NSString *> *> *)list_path:(NSString *)path in_container_of_application:(NSString *)bundleID;

/**
 Perform a hid event on the target

 @param event hid event to perform
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)hid:(FBSimulatorHIDEvent *)event;

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param longitude the longitude of the location.
 @return a Future that resolves when the location has been sent.
 */
- (FBFuture<NSNull *> *)set_location:(double)latitude longitude:(double)longitude;

/**
 Cleans the keychain of the target.

 @return A future that resolves when the keychain has been cleared.
 */
- (FBFuture<NSNull *> *)clear_keychain;

/**
 Approves the given services for an app

 @param services services to approve
 @param bundleID app to approve services for
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)approve:(NSSet<FBSettingsApprovalService> *)services for_application:(NSString *)bundleID;

/**
 Open a url on the target

 @param url url to open
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)open_url:(NSString *)url;

/**
 Focus the simulator window

 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)focus;

/**
 Update the contacts db on the device

 @param dbTarData a tar of the db file
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)update_contacts:(NSData *)dbTarData;

/**
 List the xctests installed

 @return a Future that resolves with a set of tests.
 */
- (FBFuture<NSSet<id<FBXCTestDescriptor>> *> *)list_test_bundles;

/**
 List the tests in an installed bundle

 @return a Future that resolves with names of tests in the bundle.
 */
- (FBFuture<NSArray<NSString *> *> *)list_tests_in_bundle:(NSString *)bundleID with_app:(NSString *)appPath;

/**
 Uninstall an application

 @param bundleID bundle id of the application to uninstall
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)uninstall_application:(NSString *)bundleID;

/**
 Kill an application

 @param bundleID bundle id of the application to kill
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)kill_application:(NSString *)bundleID;

/**
 Launch an application

 @param configuration the configuration to use.
 @return a Future that resolves with the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launch_app:(FBApplicationLaunchConfiguration *)configuration;

/**
 Lists Crashes according to a predicate

 @param predicate the predicate to use.
 @return a Future that resolves with the log info.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_list:(NSPredicate *)predicate;

/**
 Obtains crash log info

 @param predicate the predicate to use.
 @return a Future that resolves with the log.
 */
- (FBFuture<FBCrashLog *> *)crash_show:(NSPredicate *)predicate;

/**
 Deletes crash log info

 @param predicate the predicate to use.
 @return a Future that resolves with the logs of the deleted crashes.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_delete:(NSPredicate *)predicate;

/**
 Runs an xctest request

 @param request the request to run
 @return a Future that resolves with the xctest session.
 */
- (FBFuture<FBDeltaUpdateSession<FBXCTestDelta *> *> *)xctest_run:(id<FBXCTestRunRequest>)request;

/**
 Starts the debugserver

 @param bundleID the bundle id of the app to start for.
 @return a Future that resolves with the debugserver.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_start:(NSString *)bundleID;

/**
 Obtains the running debugserver.

 @return a Future that resolves with the debugserver.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_status;

/**
 Stops the running debugserver.

 @return a Future that resolves when the debugserver has stopped.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_stop;

/**
 Tails logs from the companion to a consumer

 @param consumer the consumer to use.
 @return a Future wrapping the log operation.
 */
- (FBFuture<id<FBLogOperation>> *)tail_companion_logs:(id<FBDataConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END
