/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSpringboardServicesClient.h"

#import "FBAMDServiceConnection.h"

NSString *const FBSpringboardServiceName = @"com.apple.springboardservices";


FBWallpaperName const FBWallpaperNameHomescreen = @"homescreen";
FBWallpaperName const FBWallpaperNameLockscreen = @"lockscreen";

@interface FBSpringboardServicesClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

typedef NSArray<NSArray<NSString *> *> *IconLayoutJSONType;

@interface FBSpringboardServicesIconContainer : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) FBSpringboardServicesClient *client;
@property (nonatomic, copy, readonly) NSArray<NSString *> *validFilenames;

@end

@implementation FBSpringboardServicesIconContainer

- (instancetype)initWithClient:(FBSpringboardServicesClient *)client
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _client = client;
  _validFilenames = @[IconPlistFile, IconJSONFile];

  return self;
}

#pragma mark FBFileContainer Implementation

static NSString *const IconPlistFile = @"icons.plist";
static NSString *const IconJSONFile = @"icons.json";

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [FBFuture futureWithResult:self.validFilenames];
}

- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath
{
  NSString *filename = containerPath.lastPathComponent;
  return [[FBFuture
    onQueue:self.client.queue resolve:^ FBFuture<IconLayoutType> * {
      if (![self.validFilenames containsObject:filename]) {
        return [[FBControlCoreError
          describeFormat:@"%@ is not one of %@", filename, [FBCollectionInformation oneLineDescriptionFromArray:self.validFilenames]]
          failFuture];
      }
      return [self.client getIconLayout];
    }]
    onQueue:self.client.queue fmap:^ FBFuture<NSString *> * (IconLayoutType layout) {
      if ([filename isEqualToString:IconJSONFile]) {
        IconLayoutJSONType jsonLayout = [FBSpringboardServicesIconContainer flattenBaseFormat:layout];
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:jsonLayout options:NSJSONWritingPrettyPrinted error:&error];
        if (!data) {
          return [FBFuture futureWithError:error];
        }
        if (![NSFileManager.defaultManager writeData:data toFile:destinationPath options:NSDataWritingAtomic error:&error]) {
          return [FBFuture futureWithError:error];
        }
        return [FBFuture futureWithResult:destinationPath];
      } else {
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:layout format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!data) {
          return [FBFuture futureWithError:error];
        }
        if (![NSFileManager.defaultManager writeData:data toFile:destinationPath options:NSDataWritingAtomic error:&error]) {
          return [FBFuture futureWithError:error];
        }
        return [FBFuture futureWithResult:destinationPath];
      }
    }];
}

- (FBFuture<NSNull *> *)copyPathOnHost:(NSURL *)sourcePath toDestination:(NSString *)destinationPath
{
  return [[self
    iconLayoutFromSourcePath:sourcePath toDestinationFile:destinationPath.lastPathComponent]
    onQueue:self.client.queue fmap:^ FBFuture<NSNull *> * (IconLayoutType layout) {
      return [self.client setIconLayout:layout];
    }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Springboard File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)movePath:(NSString *)sourcePath toDestinationPath:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Springboard File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)removePath:(NSString *)path
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Springboard File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<IconLayoutType> *)iconLayoutFromSourcePath:(NSURL *)sourcePath toDestinationFile:(NSString *)filename
{
  return [FBFuture
    onQueue:self.client.queue resolve:^ FBFuture<IconLayoutType> * {
      if ([filename isEqualToString:IconJSONFile]) {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:sourcePath options:0 error:&error];
        if (!data) {
          return [FBFuture futureWithError:error];
        }
        IconLayoutJSONType layout = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (!layout) {
          return [FBFuture futureWithError:error];
        }
        return [self convertJSONFormatToWireFormat:layout];
      }
      if ([filename isEqualToString:IconPlistFile]) {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:sourcePath options:0 error:&error];
        if (!data) {
          return [FBFuture futureWithError:error];
        }
        IconLayoutType layout = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&error];
        if (!layout) {
          return [FBFuture futureWithError:error];
        }
        return [FBFuture futureWithResult:layout];
      }
      return [[FBControlCoreError
        describeFormat:@"%@ is not one of %@", filename, [FBCollectionInformation oneLineDescriptionFromArray:self.validFilenames]]
        failFuture];
    }];
}

- (FBFuture<IconLayoutType> *)convertJSONFormatToWireFormat:(IconLayoutJSONType)jsonFormat
{
  return [[self.client
    getIconLayout]
    onQueue:self.client.queue fmap:^ FBFuture<IconLayoutType> * (IconLayoutType currentApps) {
      NSDictionary<NSString *, NSDictionary<NSString *, id> *> *iconsByBundleID = [FBSpringboardServicesIconContainer keyIconsByBundleID:currentApps];
      NSMutableArray<NSArray<NSDictionary<NSString *, id> *> *> *format = NSMutableArray.array;
      for (NSArray<NSString *> *jsonPage in jsonFormat) {
        NSMutableArray<NSDictionary<NSString *, id> *> *fullPage = NSMutableArray.array;
        for (NSString *bundleID in jsonPage) {
          NSDictionary<NSString *, id> *icon = iconsByBundleID[bundleID];
          if (!bundleID) {
            return [[FBControlCoreError
              describeFormat:@"Cannot use layout %@ is not any of %@", bundleID, [FBCollectionInformation oneLineDescriptionFromArray:iconsByBundleID.allKeys]]
              failFuture];
          }
          [fullPage addObject:icon];
        }
        [format addObject:fullPage];
      }
      return [FBFuture futureWithResult:format];
    }];
}

+ (IconLayoutJSONType)flattenBaseFormat:(IconLayoutType)baseFormat
{
  NSMutableArray<NSArray<NSString *> *> *flatFormat = NSMutableArray.array;
  for (NSArray<NSDictionary<NSString *, id> *> *basePage in baseFormat) {
    NSMutableArray<NSString *> *flatPage = NSMutableArray.array;
    for (NSDictionary<NSString *, id> *icon in basePage) {
      NSString *bundleIdentifier = icon[@"bundleIdentifier"];
      [flatPage addObject:bundleIdentifier];
    }
    [flatFormat addObject:flatPage];
  }
  return flatFormat;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)keyIconsByBundleID:(IconLayoutType)layout
{
  NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *iconsByBundleID = NSMutableDictionary.dictionary;
  for (NSArray<NSDictionary<NSString *, id> *> *page in layout) {
    for (NSDictionary<NSString *, id> *icon in page) {
      NSString *bundleIdentifier = icon[@"bundleIdentifier"];
      iconsByBundleID[bundleIdentifier] = icon;
    }
  }
  return iconsByBundleID;
}

@end

@implementation FBSpringboardServicesClient

#pragma mark Initializers

+ (instancetype)springboardServicesClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBDeviceControl.springboard_services", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithConnection:connection queue:queue logger:logger];
}

- (instancetype)initWithConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods


- (FBFuture<IconLayoutType> *)getIconLayout
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ IconLayoutType (NSError **error) {
      IconLayoutType result = [self.connection sendAndReceiveMessage:@{@"command": @"getIconState", @"formatVersion": @"2"} error:error];
      if (!result) {
        return nil;
      }
      return result;
    }];
}

static size_t IconLayoutSize = 4;

- (FBFuture<NSNull *> *)setIconLayout:(IconLayoutType)iconLayout
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNull * (NSError **error) {
      // A message is not returned upon the connection, so we just have to send the data itself and check it was acked.
      if (![self.connection sendMessage:@{@"command": @"setIconState", @"iconState": iconLayout} error:error]) {
        return nil;
      }
      // Recieve some data to know that it reached the other side, in the event of a failure we will recive no bytes. 
      NSData *data = [self.connection.serviceConnectionWrapped receive:IconLayoutSize error:error];
      if (!data) {
        return nil;
      }
      return NSNull.null;
    }];
}

- (FBFuture<NSData *> *)wallpaperImageDataForKind:(FBWallpaperName)name
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSData * (NSError **error) {
      NSDictionary<NSString *, id> *response = [self.connection sendAndReceiveMessage:@{@"command": @"getWallpaperPreviewImage", @"wallpaperName": name} error:error];
      if (!response) {
        return nil;
      }
      NSData *data = response[@"pngData"];
      if (![data isKindOfClass:NSData.class]) {
        return [[FBControlCoreError
          describeFormat:@"No pngData in response %@", response]
          fail:error];
      }
      return data;
    }];
}

- (id<FBFileContainer>)iconContainer
{
  return [[FBSpringboardServicesIconContainer alloc] initWithClient:self];
}

@end
