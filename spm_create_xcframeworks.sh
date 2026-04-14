#!/bin/bash

set -e
set -o pipefail

# Ensure Xcode projects are generated (xcodegen).
./build.sh generate

#!/bin/bash

# Function to archive and create xcframework
build_xcframework() {
    local framework_name="$1"
    local project_name="FBSimulatorControl.xcodeproj"
    local archive_path="SPM/archives/${framework_name}"
    local framework_path="${archive_path}.xcarchive/Products/Library/Frameworks/${framework_name}.framework"
    local xcframework_path="SPM/xcframeworks/${framework_name}.xcframework"
    
    # Delete existing .xcframework file if it exists
    if [ -e "$xcframework_path" ]; then
        rm -rf "$xcframework_path"
        echo "Existing xcframework deleted."
    fi
    
    # Archive the project
    xcodebuild archive -project "$project_name" -archivePath "$archive_path" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES -scheme "$framework_name" -destination generic/platform=macOS
    
    # Create xcframework
    xcodebuild -create-xcframework -framework "$framework_path" -output "$xcframework_path"
}

# Call the function with different framework names
build_xcframework "XCTestBootstrap"
build_xcframework "FBControlCore"
build_xcframework "FBSimulatorControl"
build_xcframework "FBDeviceControl"
