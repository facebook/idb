/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 Defines the content & metadata of a log.
 Lazily converts between data formats.
 */
@interface FBWritableLog : NSObject <NSCopying>

/**
 The name of the Log for uniquely identifying the log.
 */
@property (nonatomic, readonly, copy) NSString *shortName;

/**
 The File Extension of the log. The extension is used when writing to file.
 */
@property (nonatomic, readonly, copy) NSString *fileType;

/**
 A String representing this log's human readable name, as shown in error reports
 */
@property (nonatomic, readonly, copy) NSString *humanReadableName;

/**
 A String used to define where the log has been persisted to.
 This represents a more permenant or remote destination, as the File Path represented by `asPath` may be temporary.
 Can also be used to represent a URL or other identifier of a remote resource.
 */
@property (nonatomic, readonly, copy) NSString *destination;

/**
 The content of the log, as represented by NSData.
 */
@property (nonatomic, readonly, copy) NSData *asData;

/**
 The content of the log, as represented by String.
 */
@property (nonatomic, readonly, copy) NSString *asString;

/**
 The content of the log, as represented by a File Path.
 */
@property (nonatomic, readonly, copy) NSString *asPath;

/**
 The content and metadata of the log, as a NSDictionary.
 All keys and values are types allowable by NSJSONSerialization.
 */
@property (nonatomic, readonly, copy) NSDictionary *asDictionary;

/**
 Whether the log has content or is missing/empty.
 */
@property (nonatomic, readonly, assign) BOOL hasLogContent;

/**
 A Full Description of the Log.
 */
- (NSString *)debugDescription;

/**
 A Partial Description of the Log.
 */
- (NSString *)shortDescription;

@end

/**
 The Builder for a `FBWritableLog` as `FBWritableLog` is immutable.
 */
@interface FBWritableLogBuilder : NSObject

/**
 Creates a new `FBWritableLogBuilder` with an empty `writableLog`.
 */
+ (instancetype)builder;

/**
 Creates a new `FBWritableLogBuilder` taking the values from the passed throught `writableLog`.

 @param writableLog the original Writable Log to copy values from.
 @return the reciever, for chaining.
 */
+ (instancetype)builderWithWritableLog:(FBWritableLog *)writableLog;

/**
 Updates the `shortName` of the underlying `FBWritableLog`.

 @param shortName the Short Name to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateShortName:(NSString *)shortName;

/**
 Updates the `fileType` of the underlying `FBWritableLog`.

 @param fileType the File Type to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateFileType:(NSString *)fileType;

/**
 Updates the `destination` of the underlying `FBWritableLog`.

 @param destination the Destination to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateDestination:(NSString *)destination;

/**
 Updates the underlying `FBWritableLog` with Data.
 Will replace any previous path or string that represent the log.

 @param data the Date to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateData:(NSData *)data;

/**
 Updates the underlying `FBWritableLog` with a String.
 Will replace any previous data or path that represent the log.

 @param string the String to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateString:(NSString *)string;

/**
 Updates the underlying `FBWritableLog` with a File Path.
 Will replace any data or string associated with the log.

 @param path the File Path to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updatePath:(NSString *)path;

/**
 Updates the underlying `FBWritableLog` with a Path, by applying the block.
 Will replace any `logData associated with the log.

 @param block a block to populate the path with. Returning YES means the application was successful. NO otherwise.
 @return the reciever, for chaining.
 */
- (instancetype)updatePathFromBlock:( BOOL (^)(NSString *path) )block;

/**
 Updates the `humanReadableName` of the underlying `FBWritableLog`.

 @param humanReadableName the Human Readable Name to update with.
 @return the reciever, for chaining.
 */
- (instancetype)updateHumanReadableName:(NSString *)humanReadableName;

/**
 Returns a new `FBWritableLog` with the reciever's updates applied.
 */
- (FBWritableLog *)build;

@end
