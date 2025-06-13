use std::thread::sleep;
use std::time::Duration;
use std::env;

#[cfg(feature = "ffi")]
use idb_tap_simple::ffi::{IdbDirect, IdbError};

#[cfg(feature = "ffi")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("IDB Direct FFI Calibration Client");
    println!("=================================\n");
    
    // Check for command line arguments
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 && args[1] == "--help" {
        println!("Usage: {} [--auto]", args[0]);
        println!("  --auto       Run automated calibration with screenshots");
        println!("  (no args)    Run standard calibration");
        return Ok(());
    }
    
    // Initialize IDB
    println!("Initializing IDB Direct...");
    let mut idb = IdbDirect::new()?;
    
    // Connect to simulator
    let udid = "4A05B20A-349D-4EC5-B796-8F384798268B"; // Replace with your simulator UDID
    println!("Connecting to simulator {}...", udid);
    idb.connect_simulator(udid)?;
    println!("Connected successfully!\n");
    
    // Calibration targets with coordinate transformation
    let screen_height = 800.0;
    let y_offset = 62.0;
    
    let targets = [
        (88.0, screen_height - 172.0 + y_offset, "Target 1 (Top-left)"),
        (352.0, screen_height - 172.0 + y_offset, "Target 2 (Top-right)"),
        (220.0, screen_height - 430.0 + y_offset, "Target 3 (Center)"),
        (88.0, screen_height - 688.0 + y_offset, "Target 4 (Bottom-left)"),
        (352.0, screen_height - 688.0 + y_offset, "Target 5 (Bottom-right)"),
    ];
    
    // Check if automated mode
    let auto_mode = args.len() > 1 && args[1] == "--auto";
    
    if auto_mode {
        println!("Running automated calibration with screenshots...\n");
        
        // Take initial screenshot
        println!("Taking initial screenshot...");
        let screenshot = idb.screenshot()?;
        std::fs::write("ffi_calibration_0_initial.png", screenshot)?;
        println!("Saved: ffi_calibration_0_initial.png");
    }
    
    println!("Starting calibration sequence...");
    println!("Tapping {} targets\n", targets.len());
    
    sleep(Duration::from_secs(2));
    
    // Run calibration
    for (i, &(x, y, name)) in targets.iter().enumerate() {
        println!("Tapping {} at ({:.0}, {:.0})", name, x, y);
        
        // Tap down
        idb.touch_down(x, y)?;
        sleep(Duration::from_millis(50));
        
        // Tap up
        idb.touch_up(x, y)?;
        println!("  ✓ Sent tap to {}", name);
        
        if auto_mode {
            // Take screenshot after tap
            sleep(Duration::from_millis(500));
            let screenshot = idb.screenshot()?;
            let filename = format!("ffi_calibration_{}_after_{}.png", 
                                 i + 1, 
                                 name.replace(" ", "_").replace("(", "").replace(")", ""));
            std::fs::write(&filename, screenshot)?;
            println!("  Saved: {}", filename);
        }
        
        if i < targets.len() - 1 {
            println!("  Waiting 1.5 seconds before next tap...");
            sleep(Duration::from_millis(1500));
        }
    }
    
    if auto_mode {
        // Take final screenshot
        sleep(Duration::from_secs(1));
        println!("\nTaking final screenshot...");
        let screenshot = idb.screenshot()?;
        std::fs::write("ffi_calibration_6_final.png", screenshot)?;
        println!("Saved: ffi_calibration_6_final.png");
    }
    
    println!("\n✅ Calibration sequence complete!");
    println!("Check the app to see if all 5 targets were hit.");
    
    // Disconnect
    idb.disconnect()?;
    
    Ok(())
}

#[cfg(not(feature = "ffi"))]
fn main() {
    eprintln!("This binary requires the 'ffi' feature to be enabled");
    eprintln!("Run with: cargo run --features ffi --bin idb-tap-ffi");
    std::process::exit(1);
}