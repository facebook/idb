/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SimDeviceBootInfoStatus) {
  SimDeviceBootInfoStatusBooting = 0,
  SimDeviceBootInfoStatusWaitingOnBackboard = 1,
  SimDeviceBootInfoStatusWaitingOnDataMigration = 2,
  SimDeviceBootInfoStatusDataMigrationFailed = 3,
  SimDeviceBootInfoStatusWaitingOnSystemApp = 4,
  SimDeviceBootInfoStatusFinished = 4294967295,
};

@class NSDictionary, NSString;

@interface SimDeviceBootInfo : NSObject
{
    BOOL _isTerminalStatus;
    SimDeviceBootInfoStatus _status;
    double _bootElapsedTime;
    NSDictionary *_info;
}

+ (BOOL)supportsSecureCoding;
@property (nonatomic, copy) NSDictionary *info;
@property (nonatomic, assign) BOOL isTerminalStatus;
@property (nonatomic, assign) double bootElapsedTime;
@property (nonatomic, assign) SimDeviceBootInfoStatus status;
@property (readonly, nonatomic) double migrationElapsedTime;
@property (nonatomic, copy, readonly) NSString *migrationPhaseDescription;
- (void)encodeWithCoder:(id)arg1;
- (unsigned long long)hash;
- (BOOL)isEqual:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (id)initWithElapsedTime:(double)arg1 status:(unsigned int)arg2 info:(id)arg3;

@end
