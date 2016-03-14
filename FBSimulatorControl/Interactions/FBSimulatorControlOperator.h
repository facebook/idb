// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBDeviceOperator.h>

@class FBSimulator;

/**
 Operator that uses FBSimulatorControl to control DVTiPhoneSimulator/SimDevice wrapped by FBSimulator
 */
@interface FBSimulatorControlOperator : NSObject <FBDeviceOperator>

/**
 Convenience constructor

 @param simulator operated simulator
 @return FBSimulatorControlOperator, than can operate on FBSimulator class via <FBDeviceOperator> protocol.
 */
+ (instancetype)operatorWithSimulator:(FBSimulator *)simulator;

@end
