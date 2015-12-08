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

@interface FBSimulatorConfigurationVariant_Base : NSObject <NSCoding>

@end

@interface FBSimulatorConfigurationNamedDevice_iPhone4s : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone5 : FBSimulatorConfigurationVariant_Base<FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone5s : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6Plus : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6S : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPhone6SPlus : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPad2 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadRetina : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadAir : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadAir2 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@interface FBSimulatorConfigurationNamedDevice_iPadPro : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationNamedDevice>
@end

@protocol FBSimulatorConfigurationOSVersion <NSObject>

- (NSString *)osVersion;

@end

@interface FBSimulatorConfigurationOSVersion_7_1 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_0 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_1 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_2 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_3 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_8_4 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_9_0 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_9_1 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@interface FBSimulatorConfigurationOSVersion_9_2 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationOSVersion>
@end

@protocol FBSimulatorConfigurationScale <NSObject>

- (NSString *)scaleString;

@end

@interface FBSimulatorConfigurationScale_25 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationScale>
@end

@interface FBSimulatorConfigurationScale_50 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationScale>
@end

@interface FBSimulatorConfigurationScale_75 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationScale>
@end

@interface FBSimulatorConfigurationScale_100 : FBSimulatorConfigurationVariant_Base <FBSimulatorConfigurationScale>
@end

@interface FBSimulatorConfiguration ()

@property (nonatomic, strong, readwrite) id<FBSimulatorConfigurationNamedDevice> namedDevice;
@property (nonatomic, strong, readwrite) id<FBSimulatorConfigurationOSVersion> osVersion;
@property (nonatomic, strong, readwrite) id<FBSimulatorConfigurationScale> scale;
@property (nonatomic, strong, readwrite) NSLocale *locale;

@end
