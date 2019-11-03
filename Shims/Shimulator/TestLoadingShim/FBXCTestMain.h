/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/*
 Loads xctestconfiguration passed by SHIMULATOR_START_XCTEST environment variable
 and then loads xctest bundle specified in that configuration
 In case SHIMULATOR_START_XCTEST is not present, nothing will get triggered
 */
BOOL FBXCTestMain(void);
