use std::env;
use std::path::PathBuf;

fn main() {
    // Only build FFI bindings when the ffi feature is enabled
    if env::var("CARGO_FEATURE_FFI").is_ok() {
        println!("cargo:rerun-if-changed=../idb_direct/idb_direct.h");
        println!("cargo:rerun-if-changed=../idb_direct/idb_direct.m");
        
        // Get SDK path dynamically
        let sdk_path = std::process::Command::new("xcrun")
            .args(&["--sdk", "macosx", "--show-sdk-path"])
            .output()
            .expect("Failed to get SDK path")
            .stdout;
        let sdk_path = String::from_utf8(sdk_path).unwrap().trim().to_string();
        
        // Generate bindings
        let bindings = bindgen::Builder::default()
            .header("../idb_direct/idb_direct.h")
            .clang_arg(format!("-isysroot{}", sdk_path))
            .clang_arg("-x")
            .clang_arg("objective-c")
            .allowlist_function("idb_.*")
            .allowlist_type("idb_.*")
            .allowlist_var("IDB_.*")
            .parse_callbacks(Box::new(bindgen::CargoCallbacks))
            .generate()
            .expect("Unable to generate bindings");
        
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        bindings
            .write_to_file(out_path.join("bindings.rs"))
            .expect("Couldn't write bindings!");
        
        // Link to the pre-built static library
        println!("cargo:rustc-link-search=native=../build/lib");
        println!("cargo:rustc-link-lib=static=idb_direct");
        
        // Link frameworks
        println!("cargo:rustc-link-lib=framework=Foundation");
    }
}