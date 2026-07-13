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
    
    # Archive the project.
    # -module-interface-preserve-types-as-written: the FBSimulatorControl module contains a
    # class also named FBSimulatorControl, so the default module-qualified names in the emitted
    # swiftinterface ("FBSimulatorControl.FBSimulatorVideo") resolve to the class instead of the
    # module and the interface fails to compile in consumers.
    # MACH_O_TYPE=mh_dylib: the project builds static frameworks for the companion/OSS build,
    # but the distributed xcframeworks must be dynamic so the weak link against the private
    # CoreSimulator tbd stub is bound inside the dylib. A static archive would push those
    # undefined symbols onto consumers, which cannot resolve them.
    xcodebuild archive -project "$project_name" -archivePath "$archive_path" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES MACH_O_TYPE=mh_dylib OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -module-interface-preserve-types-as-written' -scheme "$framework_name" -destination generic/platform=macOS
    
    # The FBSimulatorControl module contains a class also named FBSimulatorControl, so
    # module-qualified names in the emitted swiftinterface ("FBSimulatorControl.FBSimulatorVideo")
    # resolve to the class instead of the module and fail to compile in consumers.
    # -module-interface-preserve-types-as-written (above) fixes hand-written declarations;
    # compiler-synthesized ones (CaseIterable/Equatable conformances etc.) are still qualified,
    # so strip the module qualifier from the interfaces before packaging.
    if [ "$framework_name" = "FBSimulatorControl" ]; then
        find "${framework_path}/Modules/${framework_name}.swiftmodule" -name '*.swiftinterface' \
            -exec sed -i '' -e 's/\([^A-Za-z0-9_.]\)FBSimulatorControl\./\1/g' -e 's/^FBSimulatorControl\.//' {} +
    fi

    # Create xcframework
    xcodebuild -create-xcframework -framework "$framework_path" -output "$xcframework_path"
}

# Call the function with different framework names
build_xcframework "XCTestBootstrap"
build_xcframework "FBControlCore"
build_xcframework "FBSimulatorControl"
build_xcframework "FBDeviceControl"

./verify_fbsimulatorcontrol_runtime_linkage.sh
