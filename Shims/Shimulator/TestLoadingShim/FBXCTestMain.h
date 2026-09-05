/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/*
 Loads the XCTestConfiguration at `XCTestConfigurationFilePath`, loads the test bundle it
 names, and schedules `_XCTestMain` once the host app has finished launching. Returns NO
 when the configuration or bundle cannot be loaded.
 */
BOOL FBXCTestMain(void);
