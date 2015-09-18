/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorConfiguration.h>

@protocol FBSimulatorConfigurationNamedDevice <NSObject>

- (NSString *)deviceName;

@end

@interface FBSimulatorConfigurationNamedDevice_iPhone4s : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone5 : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone5s : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6 : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6Plus : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPad2 : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadRetina : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadAir : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadAir2 : NSObject<FBSimulatorConfigurationNamedDevice>
@end

@protocol FBSimulatorConfigurationOSVersion <NSObject>

- (NSString *)osVersion;

@end

@interface FBSimulatorConfigurationOSVersion_7_1 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_0 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_1 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_2 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_3 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_4 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_9_0 : NSObject<FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfiguration ()

@property (nonatomic, strong, readwrite) id<FBSimulatorConfigurationNamedDevice> namedDevice;
@property (nonatomic, strong, readwrite) id<FBSimulatorConfigurationOSVersion> osVersion;
@property (nonatomic, strong, readwrite) NSLocale *locale;

@end
