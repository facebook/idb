/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 The Connection Reference as is typically passed around between functions.
 */
typedef void AFCConnection;
typedef AFCConnection *AFCConnectionRef;

/**
 An enum for read modes.
 */
typedef enum : uint64_t {
  FBAFCReadOnlyMode = 1,
  FBAFCreateReadAndWrite = 3
} FBAFCReadMode;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

/**
 A Structure holding references to all of the Apple File Conduit APIs.
 */
typedef struct {
  AFCConnectionRef (*Create)(void *_Nullable unknown0, int socket, void *_Nullable unknown1, void *_Nullable unknown2, void *_Nullable unknown3);
  int (*ConnectionOpen)(CFTypeRef handle, uint32_t io_timeout,CFTypeRef _Nullable *_Nullable conn);
  int (*ConnectionClose)(AFCConnectionRef connection);
  int (*DirectoryOpen)(AFCConnectionRef connection, const char *path, CFTypeRef _Nullable * _Nullable dir);
  int (*DirectoryRead)(AFCConnectionRef connection, CFTypeRef dir, char *_Nullable*_Nullable dirent);
  int (*DirectoryClose)(AFCConnectionRef connection, CFTypeRef dir);
  int (*DirectoryCreate)(AFCConnectionRef connection, const char *dir);
  int (*FileRefOpen)(AFCConnectionRef connection, const char *_Nonnull path, FBAFCReadMode mode, CFTypeRef *_Nonnull ref);
  int (*FileRefClose)(AFCConnectionRef connection, CFTypeRef ref);
  int (*FileRefSeek)(AFCConnectionRef connection, CFTypeRef ref, int64_t offset, uint64_t mode);
  int (*FileRefTell)(AFCConnectionRef connection, CFTypeRef ref, uint64_t *_Nonnull offset);
  int (*FileRefRead)(AFCConnectionRef connection, CFTypeRef ref, void *_Nonnull buf, uint64_t *_Nonnull len);
  int (*FileRefWrite)(AFCConnectionRef connection, CFTypeRef ref, const void *_Nonnull buf, uint64_t len);
  int (*RenamePath)(AFCConnectionRef connection, const char *_Nonnull path, const char *_Nonnull toPath);
  int (*RemovePath)(AFCConnectionRef connection, const char *_Nonnull path);
  int (*ConnectionProcessOperation)(AFCConnectionRef connection, CFTypeRef operation);
  int (*OperationGetResultStatus)(CFTypeRef operation);
  CFTypeRef (*OperationCreateRemovePathAndContents)(CFTypeRef allocator, CFStringRef path, void *_Nullable unknown_callback_maybe);
  CFTypeRef (*OperationGetResultObject)(CFTypeRef operation);
  int (*SetSecureContext)(CFTypeRef connection);
} AFCCalls;

#pragma clang diagnostic pop

/**
 An Object wrapper for an Apple File Conduit handle/
 */
@interface FBAFCConnection : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param connection the wrapped pointer value.
 @param calls the calls to use.
 @return a new FBAFConnection Instance.
 */
- (instancetype)initWithConnection:(AFCConnectionRef)connection calls:(AFCCalls)calls;

/**
 Constructs an FBAFCConnection from a Service Connection.

 @param serviceConnection the connection to use.
 @param calls the calls to use.
 @param error an error out for any error that occurs.
 @return an FBAFCConnection instance.
 */
+ (nullable instancetype)afcFromServiceConnection:(FBAMDServiceConnection *)serviceConnection calls:(AFCCalls)calls error:(NSError **)error;

#pragma mark Public Methods

/**
 Copies an item at the provided url into an application container.
 The source file can represent a file or a directory.

 @param source the source file on the host.
 @param containerPath the file path relative to the application container.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)copyFromHost:(NSURL *)source toContainerPath:(NSString *)containerPath error:(NSError **)error;

/**
 Creates a Directory.

 @param path the path to create.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)createDirectory:(NSString *)path error:(NSError **)error;

/**
 Get the contents of a directory.

 @param path the path to locate.
 @param error an error out for any occurs
 @return the contents of the directory.
 */
- (nullable NSArray<NSString *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error;

/**
 Get the contents of a file.

 @param path the path to read.
 @param error an error out for any occurs.
 @return the data for the file.
 */
- (nullable NSData *)contentsOfPath:(NSString *)path error:(NSError **)error;

/**
 Removes a path.

 @param path the path to remove.
 @param recursively YES to recurse, NO otherwise.
 @param error an error out for any occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)removePath:(NSString *)path recursively:(BOOL)recursively error:(NSError **)error;

#pragma mark Properties

/**
 The wrapped 'Apple File Conduit'.
 */
@property (nonatomic, assign, readonly) AFCConnectionRef connection;

/**
 The Calls to use.
 */
@property (nonatomic, assign, readonly) AFCCalls calls;

/**
 The Default Calls.
 */
@property (nonatomic, assign, readonly, class) AFCCalls defaultCalls;

@end

NS_ASSUME_NONNULL_END
