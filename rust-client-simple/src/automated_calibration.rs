use tokio::time::{sleep, Duration};
use tonic::transport::Channel;
use std::fs;

use crate::{CompanionServiceClient, CalibrationTarget, tap_target};
use crate::screenshot::{take_screenshot, save_screenshot, verify_calibration_hit};

pub async fn run_automated_calibration() -> Result<(), Box<dyn std::error::Error>> {
    println!("IDB Automated Calibration Client");
    println!("================================\n");
    
    // Connect to idb_companion
    let channel = Channel::from_static("http://localhost:10882")
        .connect()
        .await?;
    let mut client = CompanionServiceClient::new(channel);
    println!("Connected to idb_companion on localhost:10882");
    
    // Take initial screenshot
    println!("\nTaking initial screenshot...");
    save_screenshot(&mut client, "calibration_0_initial.png").await?;
    
    // Define targets with corrected coordinates
    let screen_height = 800.0;
    let y_offset = 62.0;
    
    let targets = vec![
        CalibrationTarget::new(88.0, screen_height - 172.0 + y_offset, "Target 1 (Top-left)"),
        CalibrationTarget::new(352.0, screen_height - 172.0 + y_offset, "Target 2 (Top-right)"),
        CalibrationTarget::new(220.0, screen_height - 430.0 + y_offset, "Target 3 (Center)"),
        CalibrationTarget::new(88.0, screen_height - 688.0 + y_offset, "Target 4 (Bottom-left)"),
        CalibrationTarget::new(352.0, screen_height - 688.0 + y_offset, "Target 5 (Bottom-right)"),
    ];
    
    println!("\nStarting calibration sequence...");
    println!("Will take screenshots after each tap\n");
    
    // Wait before starting
    sleep(Duration::from_secs(2)).await;
    
    // Tap each target and capture screenshots
    for (i, target) in targets.iter().enumerate() {
        tap_target(&mut client, target).await?;
        
        // Take screenshot after tap
        sleep(Duration::from_millis(500)).await; // Wait for UI to update
        let filename = format!("calibration_{}_after_{}.png", i + 1, target.name.replace(" ", "_").replace("(", "").replace(")", ""));
        save_screenshot(&mut client, &filename).await?;
        
        if i < targets.len() - 1 {
            println!("  Waiting before next tap...");
            sleep(Duration::from_millis(1000)).await;
        }
    }
    
    // Take final screenshot
    sleep(Duration::from_secs(1)).await;
    println!("\nTaking final screenshot...");
    save_screenshot(&mut client, "calibration_6_final.png").await?;
    
    println!("\n✅ Automated calibration complete!");
    println!("Screenshots saved:");
    println!("  - calibration_0_initial.png");
    for i in 1..=5 {
        println!("  - calibration_{}_after_*.png", i);
    }
    println!("  - calibration_6_final.png");
    println!("\nAnalyze the screenshots to verify all targets were hit successfully.");
    
    Ok(())
}