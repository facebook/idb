/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAFCConnection.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

static NSString *AFCCodeKey = @"AFCCode";
static NSString *AFCDomainKey = @"AFCDomain";
static size_t DataReadChunkSize = 1024;

static AFCCalls defaultCalls;

static void AFCConnectionCallback(void *connectionRefPtr, void *arg1, void *afcOperationPtr)
{
  AFCConnectionRef connection = connectionRefPtr;
  AFCOperationRef operation = afcOperationPtr;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  [logger logFormat:@"Connection %@, operation %@", connection, operation];
}

@interface FBContainedFile_AFC : NSObject <FBContainedFile>

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, assign, readonly, nullable) AFCConnectionRef connection;
@property (nonatomic, assign, readonly) AFCCalls calls;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBContainedFile_AFC

#pragma mark Initializers

- (instancetype)initWithPath:(NSString *)path connection:(AFCConnectionRef)connection calls:(AFCCalls)calls logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _path = path;
  _connection = connection;
  _calls = calls;
  _logger = logger;

  return self;
}

#pragma mark FBContainedFile Implementation

const char *SingleDot = ".";
const char *DoubleDot = "..";

- (NSArray<NSString *> *)contentsOfDirectoryWithError:(NSError **)error
{
  NSString *path = self.path;
  [self.logger logFormat:@"Listing contents of directory %@", path];
  CFTypeRef directory;
  mach_error_t result = self.calls.DirectoryOpen(self.connection, path.UTF8String, &directory);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening directory %@: %@", path, [self errorMessageWithCode:result]]
      fail:error];
  }
  NSMutableArray<NSString *> *dirs = [NSMutableArray array];
  while (YES) {
    char *listing = nil;
    self.calls.DirectoryRead(self.connection, directory, &listing);
    if (!listing) {
      break;
    }
    if (strcmp(listing, SingleDot) == 0 || strcmp(listing, DoubleDot) == 0) {
      continue;
    }

    [dirs addObject:[NSString stringWithUTF8String:listing]];
  }

  self.calls.DirectoryClose(self.connection, directory);
  [self.logger logFormat:@"Contents of directory %@ %@", path, [FBCollectionInformation oneLineDescriptionFromArray:dirs]];
  return [NSArray arrayWithArray:dirs];
}

- (NSData *)contentsOfFileWithError:(NSError **)error
{
  NSString *path = self.path;
  [self.logger logFormat:@"Contents of path %@", path];
  NSMutableData *data = NSMutableData.data;
  int result = [self enumerateContentsOfRemoteFile:path chunkMaxSize:DataReadChunkSize enumerator:^(void *buffer, size_t size) {
    [data appendBytes:buffer length:size];
    return 0;
  }];
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when reading remote file %@: %@", path, [self errorMessageWithCode:result]]
      fail:error];
  }
  return data;
}

- (BOOL)removeItemWithError:(NSError **)error
{
  NSString *path = self.path;
  [self.logger logFormat:@"Removing path %@ and contents", path];
  AFCOperationRef operation = self.calls.OperationCreateRemovePathAndContents(
    CFGetAllocator(self.connection),
    (__bridge CFStringRef _Nonnull)(path),
    NULL
  );
  if (operation == nil) {
    return [[FBDeviceControlError
      describeFormat:@"Operation for path removal %@ couldn't be created", path]
      failBool:error];
  }
  int op_result = self.calls.ConnectionProcessOperation(self.connection, operation);
  if (op_result != 0) {
    CFRelease(operation);
    return [[FBDeviceControlError
      describeFormat:@"Operation couldn't be processed (%d)", op_result]
      failBool:error];
  }
  BOOL success = [self afcOperationSucceeded:operation error:error];
  CFRelease(operation);
  return success;
}

- (BOOL)moveTo:(id<FBContainedFile>)destination error:(NSError **)error
{
  if (![destination isKindOfClass:self.class]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot move a file from AFC to %@", destination]
      failBool:error];
  }
  FBContainedFile_AFC *destinationAFC = (FBContainedFile_AFC *) destination;
  NSString *sourcePath = self.path;
  NSString *destinationPath = destinationAFC.path;
  mach_error_t result = self.calls.RenamePath(self.connection, sourcePath.UTF8String, destinationPath.UTF8String);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when renaming from %@ to %@: %@", sourcePath, destinationPath, [self errorMessageWithCode:result]]
      failBool:error];
  }
  return YES;
}

- (BOOL)createDirectoryWithError:(NSError **)error
{
  NSString *path = self.path;
  [self.logger logFormat:@"Creating Directory %@", path];
  mach_error_t result = self.calls.DirectoryCreate(self.connection, [path UTF8String]);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when creating directory: %@", [self errorMessageWithCode:result]]
      failBool:error];
  }
  [self.logger logFormat:@"Created Directory %@", path];
  return YES;
}

static const char *FileInfoFileType = "st_ifmt";
static const char *FileTypeDirectory = "S_IFDIR";

- (BOOL)fileExistsIsDirectory:(BOOL *)isDirectoryOut
{
  AFCDictionaryRef info = NULL;
  int status = self.calls.FileInfoOpen(self.connection, self.path.UTF8String, &info);
  if (status != 0) {
    return NO;
  }
  if (isDirectoryOut != NULL) {
    const char *fileType;
    status = self.calls.KeyValueRead(info, &FileInfoFileType, &fileType);
    *isDirectoryOut = (status == 0 && strcmp(fileType, FileTypeDirectory) == 0) ? YES : NO;
  }
  self.calls.KeyValueClose(info);
  return YES;
}

- (BOOL)populateHostPathWithContents:(NSString *)path error:(NSError **)error
{
  BOOL afcPathIsDirectory = NO;
  if (![self fileExistsIsDirectory:&afcPathIsDirectory]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot pull %@ to host path %@, afc path does not exist", self, path]
      failBool:error];
  }
  if (afcPathIsDirectory) {
    return [self populateHostPathWithContentsOfDirectory:path error:error];
  } else {
    return [self populateHostPathWithContentsOfFile:path error:error];
  }
}

- (BOOL)populateWithContentsOfHostPath:(NSString *)path error:(NSError **)error
{
  BOOL hostPathIsDirectory;
  if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&hostPathIsDirectory]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot push %@ to device path %@, host path does not exist", path, self]
      failBool:error];
  }
  if (hostPathIsDirectory) {
    return [self populateWithContentsOfHostDirectory:path error:error];
  } else {
    return [self populateWithContentsOfHostFile:path error:error];
  }
}

- (id<FBContainedFile>)fileByAppendingPathComponent:(NSString *)component error:(NSError **)error
{
  return [self afcFileByAppendingPathComponent:component];
}

- (NSString *)pathOnHostFileSystem
{
  return nil;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %@", self.path, self.connection];
}

#pragma mark Private

- (id<FBContainedFile>)afcFileByAppendingPathComponent:(NSString *)component
{
  return [[FBContainedFile_AFC alloc] initWithPath:[self.path stringByAppendingPathComponent:component] connection:self.connection calls:self.calls logger:self.logger];
}

- (BOOL)populateHostPathWithContentsOfDirectory:(NSString *)hostDirectory error:(NSError **)error
{
  // Get the contents of the AFC Dir
  NSArray<NSString *> *contents = [self contentsOfDirectoryWithError:error];
  if (!contents) {
    return NO;
  }
  // Create the destination directory if required.
  if (![NSFileManager.defaultManager createDirectoryAtPath:hostDirectory withIntermediateDirectories:YES attributes:@{} error:error]) {
    return NO;
  }
  // Enumerate all AFC subpaths, pulling each of those.
  for (NSString *path in contents) {
    id<FBContainedFile> afcNext = [self afcFileByAppendingPathComponent:path];
    NSString *hostNext = [hostDirectory stringByAppendingPathComponent:path];
    if (![afcNext populateHostPathWithContents:hostNext error:error]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)populateHostPathWithContentsOfFile:(NSString *)hostFile error:(NSError **)error
{
  NSData *data = [self contentsOfFileWithError:error];
  if (!data) {
    return NO;
  }
  if (![data writeToFile:hostFile options:0 error:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)populateWithContentsOfHostDirectory:(NSString *)hostDirectory error:(NSError **)error
{
  // First create the remote directory.
  BOOL success = [self createDirectoryWithError:error];
  if (!success) {
    return NO;
  }
  // Then enumerate and copy the contents
  [self.logger logFormat:@"Copying from %@ to %@", hostDirectory, self];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSDirectoryEnumerator<NSURL *> *urls = [fileManager
    enumeratorAtURL:[NSURL fileURLWithPath:hostDirectory]
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
    errorHandler:NULL];

  for (NSURL *url in urls) {
    NSString *hostNext = url.path;
    id<FBContainedFile> afcNext = [self afcFileByAppendingPathComponent:hostNext.lastPathComponent];
    if (![afcNext populateWithContentsOfHostPath:hostNext error:error]) {
      [self.logger logFormat:@"Failed to copy %@ to %@ with error %@", url, self, *error];
      return NO;
    }
  }
  [self.logger logFormat:@"Copied from %@ to %@", hostDirectory, self];
  return YES;
}

- (BOOL)populateWithContentsOfHostFile:(NSString *)hostFile error:(NSError **)error
{
  [self.logger logFormat:@"Copying %@ to %@", hostFile, self];
  NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:hostFile];
  if (!inputStream) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to open host file %@", hostFile]
      failBool:error];
  }
  [inputStream open];
  CFTypeRef fileReference;
  mach_error_t result = self.calls.FileRefOpen(self.connection, self.path.UTF8String, FBAFCreateReadAndWrite, &fileReference);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening remote file %@: %@", self.path, [self errorMessageWithCode:result]]
      failBool:error];
  }
  int writeResult = [FBContainedFile_AFC enumerateContentsOfHostFile:inputStream chunkMaxSize:DataReadChunkSize enumerator:^(void *buffer, size_t size){
    return self.calls.FileRefWrite(self.connection, fileReference, buffer, size);
  }];
  self.calls.FileRefClose(self.connection, fileReference);
  [inputStream close];
  if (writeResult != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when writing file %@: %@", self, [self errorMessageWithCode:writeResult]]
      failBool:error];
  }
  [self.logger logFormat:@"Copied from %@ to %@", hostFile, self];
  return YES;
}

- (BOOL)afcOperationSucceeded:(AFCOperationRef)operation error:(NSError **)error
{
  int status = self.calls.OperationGetResultStatus(operation);
  if (status == 0) {
    return YES;
  }
  NSDictionary<NSString *, id> *infoDictionary = (__bridge id)(self.calls.OperationGetResultObject(operation));
  if (![infoDictionary isKindOfClass:[NSDictionary class]]) {
    return [[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      failBool:error];
  }

  NSNumber *code = infoDictionary[AFCCodeKey];
  NSString *domain = infoDictionary[AFCDomainKey];
  if (!code || ![code respondsToSelector:@selector(integerValue)] || !domain || ![domain isKindOfClass:NSString.class]) {
    return [[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      failBool:error];
  }
  return [[[FBDeviceControlError
    describeFormat:@"AFCOperation failed. underlying error: %@", infoDictionary]
    code:code.integerValue]
    failBool:error];
}

- (NSString *)errorMessageWithCode:(int)code
{
  const char *name = self.calls.ErrorString(code);
  NSDictionary<NSString *, id> *info = CFBridgingRelease(self.calls.ConnectionCopyLastErrorInfo(self.connection));
  return [NSString stringWithFormat:@"%s %@", name, [FBCollectionInformation oneLineDescriptionFromDictionary:info]];
}

+ (BOOL)hostPathIsDirectory:(NSString *)path
{
  BOOL isDir = NO;
  return ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir);
}

+ (int)enumerateContentsOfHostFile:(NSInputStream *)hostFileStream chunkMaxSize:(size_t)chunkMaxSize enumerator:(int(^)(void *, size_t))enumerator
{
  int result = 0;
  void *buffer = malloc(chunkMaxSize);
  while (hostFileStream.hasBytesAvailable) {
    NSInteger readResult = [hostFileStream read:buffer maxLength:chunkMaxSize];
    if (readResult == 0) {
      break;
    }
    if (readResult == -1) {
      break;
    }
    size_t readSize = (size_t) readResult;
    result = enumerator(buffer, readSize);
    if (result != 0) {
      break;
    }
  }
  free(buffer);
  return result;
}

- (int)enumerateContentsOfRemoteFile:(NSString *)remoteFilePath chunkMaxSize:(size_t)chunkMaxSize enumerator:(int(^)(void *, size_t))enumerator
{
  // Open the remote file.
  CFTypeRef file;
  mach_error_t openResult = self.calls.FileRefOpen(self.connection, remoteFilePath.UTF8String, FBAFCReadOnlyMode, &file);
  if (openResult != 0) {
    return openResult;
  }
  // Obtain the remote file size using 'mode 2'
  self.calls.FileRefSeek(self.connection, file, 0, 2);
  uint64_t remoteFileSize = 0;
  self.calls.FileRefTell(self.connection, file, &remoteFileSize);
  self.calls.FileRefSeek(self.connection, file, 0, 0);
  // Construct the buffer to read into.
  void *buffer = malloc(chunkMaxSize);
  uint64_t bytesRemaining = remoteFileSize;
  // Enumerate the stream until there are no bytes remaining.
  int readResult = 0;
  while (bytesRemaining > 0) {
    uint64_t readBytes = MIN(chunkMaxSize, bytesRemaining);
    readResult = self.calls.FileRefRead(self.connection, file, buffer, &readBytes);
    if (readResult != 0) {
      break;
    }
    readResult = enumerator(buffer, readBytes);
    if (readResult != 0) {
      break;
    }
    NSAssert(readBytes <= bytesRemaining, @"Read %llu bytes, when only %llu should have been read!!", readBytes, bytesRemaining);
    bytesRemaining = bytesRemaining - readBytes;
  }
  free(buffer);
  self.calls.FileRefClose(self.connection, file);
  return readResult;
}

@end

@implementation FBAFCConnection

#pragma mark Initializers

- (instancetype)initWithConnection:(AFCConnectionRef)connection calls:(AFCCalls)calls logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _calls = calls;
  _logger = logger;

  return self;
}

+ (FBFutureContext<FBAFCConnection *> *)afcFromServiceConnection:(FBAMDServiceConnection *)serviceConnection calls:(AFCCalls)calls logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  return [[FBFuture
    onQueue:queue resolve:^{
      FBAFCConnection *connection = [serviceConnection asAFCConnectionWithCalls:calls callback:AFCConnectionCallback logger:logger];
      if (![connection connectionIsValid]) {
        return [[FBDeviceControlError
          describeFormat:@"Created AFC Connection %@ is not valid", connection]
          failFuture];
      }
      return [FBFuture futureWithResult:connection];
    }]
    onQueue:queue contextualTeardown:^(FBAFCConnection *connection, FBFutureState __) {
      [connection closeWithError:nil];
      return FBFuture.empty;
    }];
}

#pragma mark Public

- (id<FBContainedFile>)containedFileForPath:(NSString *)path;
{
  return [[FBContainedFile_AFC alloc] initWithPath:path connection:self.connection calls:self.calls logger:self.logger];
}

- (BOOL)closeWithError:(NSError **)error
{
  if (!_connection) {
    return [[FBDeviceControlError
      describe:@"Cannot close a non-existant connection"]
      failBool:error];
  }
  NSString *connectionDescription = CFBridgingRelease(CFCopyDescription(self.connection));
  [self.logger logFormat:@"Closing %@", connectionDescription];
  int status = self.calls.ConnectionClose(self.connection);
  if (status != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to close connection with error %d", status]
      failBool:error];
  }
  [self.logger logFormat:@"Closed AFC Connection %@", connectionDescription];
  // AFCConnectionClose does release the connection.
  _connection = NULL;
  return YES;
}

#pragma mark Properties

- (id<FBContainedFile>)rootContainedFile
{
  return [[FBContainedFile_AFC alloc] initWithPath:@"/" connection:self.connection calls:self.calls logger:self.logger];
}

#pragma mark AFC Calls

+ (AFCCalls)defaultCalls
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [self populateCallsFromMobileDevice:&defaultCalls];
  });
  return defaultCalls;
}

#pragma mark Private

- (BOOL)connectionIsValid
{
  return (BOOL) self.calls.ConnectionIsValid(self.connection);
}

+ (void)populateCallsFromMobileDevice:(AFCCalls *)calls
{
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.mobiledevice"] dlopenExecutablePath];
  calls->ConnectionClose = FBGetSymbolFromHandle(handle, "AFCConnectionClose");
  calls->ConnectionCopyLastErrorInfo = FBGetSymbolFromHandle(handle, "AFCConnectionCopyLastErrorInfo");
  calls->ConnectionIsValid = FBGetSymbolFromHandle(handle, "AFCConnectionIsValid");
  calls->ConnectionOpen = FBGetSymbolFromHandle(handle, "AFCConnectionOpen");
  calls->ConnectionProcessOperation = FBGetSymbolFromHandle(handle, "AFCConnectionProcessOperation");
  calls->Create = FBGetSymbolFromHandle(handle, "AFCConnectionCreate");
  calls->DirectoryClose = FBGetSymbolFromHandle(handle, "AFCDirectoryClose");
  calls->DirectoryCreate = FBGetSymbolFromHandle(handle, "AFCDirectoryCreate");
  calls->DirectoryOpen = FBGetSymbolFromHandle(handle, "AFCDirectoryOpen");
  calls->DirectoryRead = FBGetSymbolFromHandle(handle, "AFCDirectoryRead");
  calls->ErrorString = FBGetSymbolFromHandle(handle, "AFCErrorString");
  calls->FileInfoOpen = FBGetSymbolFromHandle(handle, "AFCFileInfoOpen");
  calls->FileRefClose = FBGetSymbolFromHandle(handle, "AFCFileRefClose");
  calls->FileRefOpen = FBGetSymbolFromHandle(handle, "AFCFileRefOpen");
  calls->FileRefRead = FBGetSymbolFromHandle(handle, "AFCFileRefRead");
  calls->FileRefSeek = FBGetSymbolFromHandle(handle, "AFCFileRefSeek");
  calls->FileRefTell = FBGetSymbolFromHandle(handle, "AFCFileRefTell");
  calls->FileRefWrite = FBGetSymbolFromHandle(handle, "AFCFileRefWrite");
  calls->KeyValueClose = FBGetSymbolFromHandle(handle, "AFCKeyValueClose");
  calls->KeyValueRead = FBGetSymbolFromHandle(handle, "AFCKeyValueRead");
  calls->OperationCreateRemovePathAndContents = FBGetSymbolFromHandle(handle, "AFCOperationCreateRemovePathAndContents");
  calls->OperationGetResultObject = FBGetSymbolFromHandle(handle, "AFCOperationGetResultObject");
  calls->OperationGetResultStatus = FBGetSymbolFromHandle(handle, "AFCOperationGetResultStatus");
  calls->RemovePath = FBGetSymbolFromHandle(handle, "AFCRemovePath");
  calls->RenamePath = FBGetSymbolFromHandle(handle, "AFCRenamePath");
  calls->SetSecureContext = FBGetSymbolFromHandle(handle, "AFCConnectionSetSecureContext");
}

@end
