/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSDictionary, NSOrderedSet, NSSet, NSString;

@interface DVTDeviceType : NSObject
{
    NSString *_identifier;
    NSString *_name;
    NSString *_UTI;
    NSOrderedSet *_supportedArchitectures;
    NSString *_deviceSpecifierPrefix;
    NSDictionary *_deviceSpecifierOptionDefaults;
    NSSet *_knownDeviceSpecifierOptions;
    NSSet *_requiredDeviceSpecifierOptions;
}

+ (id)deviceTypeWithIdentifier:(id)arg1;
+ (void)initialize;
@property(readonly, copy) NSSet *requiredDeviceSpecifierOptions; // @synthesize requiredDeviceSpecifierOptions=_requiredDeviceSpecifierOptions;
@property(readonly, copy) NSSet *knownDeviceSpecifierOptions; // @synthesize knownDeviceSpecifierOptions=_knownDeviceSpecifierOptions;
@property(readonly, copy) NSDictionary *deviceSpecifierOptionDefaults; // @synthesize deviceSpecifierOptionDefaults=_deviceSpecifierOptionDefaults;
@property(readonly, copy) NSString *deviceSpecifierPrefix; // @synthesize deviceSpecifierPrefix=_deviceSpecifierPrefix;
@property(readonly, copy) NSOrderedSet *supportedArchitectures; // @synthesize supportedArchitectures=_supportedArchitectures;
@property(readonly, copy) NSString *UTI; // @synthesize UTI=_UTI;
@property(readonly, copy) NSString *name; // @synthesize name=_name;
@property(readonly, copy) NSString *identifier; // @synthesize identifier=_identifier;

- (id)description;
- (id)initWithExtension:(id)arg1;

@end

