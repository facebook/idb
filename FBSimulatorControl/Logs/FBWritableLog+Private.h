/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBWritableLog.h>

@interface FBWritableLog ()

@property (nonatomic, copy, readwrite) NSString *shortName;
@property (nonatomic, copy, readwrite) NSString *fileType;
@property (nonatomic, copy, readwrite) NSString *humanReadableName;
@property (nonatomic, copy, readwrite) NSString *destination;

@property (nonatomic, copy, readwrite) NSData *logData;
@property (nonatomic, copy, readwrite) NSString *logString;
@property (nonatomic, copy, readwrite) NSString *logPath;

@end

/**
 A representation of a Writable Log, backed by NSData.
 */
@interface FBWritableLog_Data : FBWritableLog

@end

/**
 A representation of a Writable Log, backed by an NSString.
 */
@interface FBWritableLog_String : FBWritableLog

@end

/**
 A representation of a Writable Log, backed by a File Path.
 */
@interface FBWritableLog_Path : FBWritableLog

@end

/**
 A representation of a Writable Log, where the log is known to not exist.
 */
@interface FBWritableLog_Empty : FBWritableLog

@end
