/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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

static AFCCalls defaultCalls;

static void AFCConnectionCallback(void *connectionRefPtr, void *arg1, void *afcOperationPtr)
{
  AFCConnectionRef connection = connectionRefPtr;
  AFCOperationRef operation = afcOperationPtr;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  [logger logFormat:@"Connection %@, operation %@", connection, operation];
}

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
      AFCConnectionRef afcConnection = calls.Create(
        0x0,
        serviceConnection.socket,
        0x0,
        AFCConnectionCallback,
        0x0
      );
      // We need to apply the Secure Context if it's present on the service connection.
      AMSecureIOContext secureIOContext = serviceConnection.secureIOContext;
      if (secureIOContext != NULL) {
        calls.SetSecureContext(afcConnection, secureIOContext);
      }
      FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:afcConnection calls:calls logger:logger];
      if (![connection connectionIsValid]) {
        return [[FBDeviceControlError
          describeFormat:@"Connection is not valid"]
          failFuture];
      }
      return [FBFuture futureWithResult:connection];
    }]
    onQueue:queue contextualTeardown:^(FBAFCConnection *connection, FBFutureState __) {
      [connection closeWithError:nil];
      return FBFuture.empty;
    }];
}

#pragma mark Public Methods

- (BOOL)copyFromHost:(NSURL *)url toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  NSNumber *isDir;
  if (![url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:error]) {
    return NO;
  }
  if (isDir.boolValue) {
    containerPath = [containerPath stringByAppendingPathComponent:url.lastPathComponent];
    BOOL success = [self createDirectory:containerPath error:error];
    if (!success) {
      return NO;
    }
    return [self copyContentsOfHostDirectory:url toContainerPath:containerPath error:error];
  } else {
    return [self copyFileFromHost:url toContainerPath:[containerPath stringByAppendingPathComponent:url.lastPathComponent] error:error];
  }
}

- (BOOL)createDirectory:(NSString *)path error:(NSError **)error
{
  [self.logger logFormat:@"Creating Directory %@", path];
  mach_error_t result = self.calls.DirectoryCreate(self.connection, [path UTF8String]);
  if (result != 0) {
    return [[[FBDeviceControlError
      describeFormat:@"Error when creating directory: %@", [self errorMessageWithCode:result]]
      logger:self.logger]
      failBool:error];
  }
  [self.logger logFormat:@"Created Directory %@", path];
  return YES;
}

const char *SingleDot = ".";
const char *DoubleDot = "..";

- (NSArray<NSString *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error
{
  [self.logger logFormat:@"Listing contents of directory %@", path];
  CFTypeRef directory;
  mach_error_t result = self.calls.DirectoryOpen(self.connection, path.UTF8String, &directory);
  if (result != 0) {
    return [[[FBDeviceControlError
      describeFormat:@"Error when opening directory: %@", [self errorMessageWithCode:result]]
      logger:self.logger]
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
  [self.logger logFormat:@"Contents of directory %@", [FBCollectionInformation oneLineDescriptionFromArray:dirs]];
  return [NSArray arrayWithArray:dirs];
}

- (NSData *)contentsOfPath:(NSString *)path error:(NSError **)error
{
  [self.logger logFormat:@"Contents of path %@", path];
  CFTypeRef file;
  mach_error_t result = self.calls.FileRefOpen(self.connection, [path UTF8String], FBAFCReadOnlyMode, &file);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening file: %@", [self errorMessageWithCode:result]]
      fail:error];
  }
  self.calls.FileRefSeek(self.connection, file, 0, 2);
  uint64_t offset = 0;
  self.calls.FileRefTell(self.connection, file, &offset);
  NSMutableData *buffer = [[NSMutableData alloc] initWithLength:offset];
  uint64_t len = offset;
  uint64_t toRead = len;
  self.calls.FileRefSeek(self.connection, file, 0, 0);
  while (toRead > 0) {
    uint64_t read = toRead;
    result = self.calls.FileRefRead(self.connection, file, [buffer mutableBytes] + (len - toRead), &read);
    toRead -= read;
    if (result != 0) {
      self.calls.FileRefClose(self.connection, file);
      return [[[FBDeviceControlError
        describeFormat:@"Error when reading file: %@", [self errorMessageWithCode:result]]
        logger:self.logger]
        fail:error];
    }
  }
  self.calls.FileRefClose(self.connection, file);
  [self.logger logFormat:@"Read %lu bytes from path %@", buffer.length, path];
  return buffer;
}

- (BOOL)removePath:(NSString *)path recursively:(BOOL)recursively error:(NSError **)error
{
  if (recursively) {
    return [self removePathAndContents:path error:error];
  } else {
    [self.logger logFormat:@"Removing file path %@", path];
    mach_error_t result = self.calls.RemovePath(self.connection, [path UTF8String]);
    if (result != 0) {
      return [[[FBDeviceControlError
        describeFormat:@"Error when removing path: %@", [self errorMessageWithCode:result]]
        logger:self.logger]
        failBool:error];
    }
    [self.logger logFormat:@"Removed file path %@", path];
    return YES;
  }
}

- (BOOL)renamePath:(NSString *)path destination:(NSString *)destination error:(NSError **)error
{
  mach_error_t result = self.calls.RenamePath(self.connection, path.UTF8String, destination.UTF8String);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when renaming from %@ to %@: %@", path, destination, [self errorMessageWithCode:result]]
      failBool:error];
  }
  return YES;
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
    return [[[FBDeviceControlError
      describeFormat:@"Failed to close connection with error %d", status]
      logger:self.logger]
      failBool:error];
  }
  [self.logger logFormat:@"Closed AFC Connection %@", connectionDescription];
  // AFCConnectionClose does release the connection.
  _connection = NULL;
  return YES;
}

#pragma mark Private

- (BOOL)copyFileFromHost:(NSURL *)path toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  [self.logger logFormat:@"Copying %@ to %@", path, containerPath];
  NSData *data = [NSData dataWithContentsOfURL:path];
  if (!data) {
    return [[FBDeviceControlError
      describeFormat:@"Could not find file on host: %@", path]
      failBool:error];
  }

  CFTypeRef fileReference;
  mach_error_t result = self.calls.FileRefOpen(self.connection, containerPath.UTF8String, FBAFCreateReadAndWrite, &fileReference);
  if (result != 0) {
    return [[[FBDeviceControlError
      describeFormat:@"Error when opening file: %@", [self errorMessageWithCode:result]]
      logger:self.logger]
      failBool:error];
  }

  __block mach_error_t writeResult = 0;
  [data enumerateByteRangesUsingBlock:^(const void *bytes, NSRange byteRange, BOOL *stop) {
    if (byteRange.length == 0) {
      return;
    }
    writeResult = self.calls.FileRefWrite(self.connection, fileReference, bytes, byteRange.length);
    if (writeResult != 0) {
      *stop = YES;
    }
  }];
  self.calls.FileRefClose(self.connection, fileReference);
  if (writeResult != 0) {
    return [[[FBDeviceControlError
      describeFormat:@"Error when writing file: %@", [self errorMessageWithCode:writeResult]]
      logger:self.logger]
      failBool:error];
  }
  [self.logger logFormat:@"Copied from %@ to %@", path, containerPath];
  return YES;
}

- (BOOL)copyContentsOfHostDirectory:(NSURL *)path toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  [self.logger logFormat:@"Copying from %@ to %@", path, containerPath];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSDirectoryEnumerator<NSURL *> *urls = [fileManager
    enumeratorAtURL:path
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
    errorHandler:NULL];

  for (NSURL *url in urls) {
    BOOL success = [self copyFromHost:url toContainerPath:containerPath error:error];
    if (!success) {
      [self.logger logFormat:@"Failed to copy %@ to %@ with error %@", path, containerPath, *error];
      return NO;
    }
  }
  [self.logger logFormat:@"Copied from %@ to %@", path, containerPath];
  return YES;
}

- (BOOL)removePathAndContents:(NSString *)path error:(NSError **)error
{
  [self.logger logFormat:@"Removing path %@ and contents", path];
  AFCOperationRef operation = self.calls.OperationCreateRemovePathAndContents(
    CFGetAllocator(self.connection),
    (__bridge CFStringRef _Nonnull)(path),
    NULL
  );
  if (operation == nil) {
    return [[[FBDeviceControlError
      describe:@"Operation couldn't be created"]
      logger:self.logger]
      failBool:error];
  }
  int op_result = self.calls.ConnectionProcessOperation(self.connection, operation);
  if (op_result != 0) {
    CFRelease(operation);
    return [[[FBDeviceControlError
      describeFormat:@"Operation couldn't be processed (%d)", op_result]
      logger:self.logger]
      failBool:error];
  }
  BOOL success = [self afcOperationSucceeded:operation error:error];
  CFRelease(operation);
  return success;
}

- (BOOL)afcOperationSucceeded:(AFCOperationRef)operation error:(NSError **)error
{
  int status = self.calls.OperationGetResultStatus(operation);
  if (status == 0) {
    return YES;
  }
  NSDictionary<NSString *, id> *infoDictionary = (__bridge id)(self.calls.OperationGetResultObject(operation));
  if (![infoDictionary isKindOfClass:[NSDictionary class]]) {
    return [[[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      logger:self.logger]
      failBool:error];
  }

  NSNumber *code = infoDictionary[AFCCodeKey];
  NSString *domain = infoDictionary[AFCDomainKey];
  if (!code || ![code respondsToSelector:@selector(integerValue)] || !domain || ![domain isKindOfClass:NSString.class]) {
    return [[[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      logger:self.logger]
      failBool:error];
  }
  return [[[[FBDeviceControlError
    describeFormat:@"AFCOperation failed. underlying error: %@", infoDictionary]
    code:code.integerValue]
    logger:self.logger]
    failBool:error];
}

- (NSString *)errorMessageWithCode:(int)code
{
  const char *name = self.calls.ErrorString(code);
  NSDictionary<NSString *, id> *info = CFBridgingRelease(self.calls.ConnectionCopyLastErrorInfo(self.connection));
  return [NSString stringWithFormat:@"%s %@", name, [FBCollectionInformation oneLineDescriptionFromDictionary:info]];
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
  calls->FileRefClose = FBGetSymbolFromHandle(handle, "AFCFileRefClose");
  calls->FileRefOpen = FBGetSymbolFromHandle(handle, "AFCFileRefOpen");
  calls->FileRefRead = FBGetSymbolFromHandle(handle, "AFCFileRefRead");
  calls->FileRefSeek = FBGetSymbolFromHandle(handle, "AFCFileRefSeek");
  calls->FileRefTell = FBGetSymbolFromHandle(handle, "AFCFileRefTell");
  calls->FileRefWrite = FBGetSymbolFromHandle(handle, "AFCFileRefWrite");
  calls->OperationCreateRemovePathAndContents = FBGetSymbolFromHandle(handle, "AFCOperationCreateRemovePathAndContents");
  calls->OperationGetResultObject = FBGetSymbolFromHandle(handle, "AFCOperationGetResultObject");
  calls->OperationGetResultStatus = FBGetSymbolFromHandle(handle, "AFCOperationGetResultStatus");
  calls->RemovePath = FBGetSymbolFromHandle(handle, "AFCRemovePath");
  calls->RenamePath = FBGetSymbolFromHandle(handle, "AFCRenamePath");
  calls->SetSecureContext = FBGetSymbolFromHandle(handle, "AFCConnectionSetSecureContext");
}

@end
