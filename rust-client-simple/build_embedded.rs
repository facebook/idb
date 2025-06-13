// build_embedded.rs - Build script for embedded companion

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=../idb_direct/idb_direct_embedded.h");
    println!("cargo:rerun-if-changed=../idb_direct/idb_direct_embedded.m");
    println!("cargo:rerun-if-changed=build_embedded.rs");
    
    let project_root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap())
        .parent()
        .unwrap()
        .to_path_buf();
    
    // Build embedded companion library if not exists
    let lib_path = project_root.join("build/lib/libidb_embedded.a");
    if !lib_path.exists() {
        println!("Building embedded companion library...");
        
        let output = Command::new("bash")
            .arg(project_root.join("build_embedded_companion.sh"))
            .output()
            .expect("Failed to execute build script");
        
        if !output.status.success() {
            panic!(
                "Failed to build embedded companion:\n{}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }
    
    // Generate bindings
    let bindings = bindgen::Builder::default()
        .header(project_root.join("idb_direct/idb_direct_embedded.h").to_str().unwrap())
        .clang_arg("-x")
        .clang_arg("objective-c")
        .clang_arg(format!("-F{}/build/Build/Products/Debug", project_root.display()))
        .allowlist_function("idb_companion_.*")
        .allowlist_type("idb_.*")
        .allowlist_type("Idb.*")
        .allowlist_var("IDB_.*")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        .generate()
        .expect("Unable to generate bindings");
    
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("embedded_bindings.rs"))
        .expect("Couldn't write bindings!");
    
    // Link libraries
    println!("cargo:rustc-link-search=native={}/build/lib", project_root.display());
    println!("cargo:rustc-link-lib=static=idb_embedded");
    
    // Link system frameworks
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=framework=CoreGraphics");
    println!("cargo:rustc-link-lib=framework=CoreSimulator");
    
    // Link idb frameworks
    println!("cargo:rustc-link-search=framework={}/build/Build/Products/Debug", project_root.display());
    println!("cargo:rustc-link-lib=framework=FBControlCore");
    println!("cargo:rustc-link-lib=framework=FBSimulatorControl");
    println!("cargo:rustc-link-lib=framework=FBDeviceControl");
    println!("cargo:rustc-link-lib=framework=XCTestBootstrap");
    println!("cargo:rustc-link-lib=framework=CompanionLib");
    println!("cargo:rustc-link-lib=framework=IDBCompanionUtilities");
    
    // Link Swift runtime (required for IDBCompanionUtilities)
    println!("cargo:rustc-link-lib=dylib=swiftCore");
    println!("cargo:rustc-link-lib=dylib=swiftFoundation");
    println!("cargo:rustc-link-search=native=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx");
}