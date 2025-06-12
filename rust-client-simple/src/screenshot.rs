use tonic::{transport::Channel, Request, Status};
use std::fs;
use std::path::Path;

use crate::proto::*;
use crate::CompanionServiceClient;

impl CompanionServiceClient {
    pub async fn screenshot(
        &mut self,
        request: Request<ScreenshotRequest>,
    ) -> Result<tonic::Response<ScreenshotResponse>, Status> {
        self.inner.ready().await.map_err(|e| {
            Status::new(
                tonic::Code::Unknown,
                format!("Service was not ready: {}", e),
            )
        })?;
        let codec = tonic::codec::ProstCodec::default();
        let path = http::uri::PathAndQuery::from_static("/idb.CompanionService/screenshot");
        self.inner.unary(request, path, codec).await
    }
}

pub async fn take_screenshot(client: &mut CompanionServiceClient) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let request = Request::new(ScreenshotRequest {});
    let response = client.screenshot(request).await?;
    let screenshot = response.into_inner();
    
    println!("Screenshot captured: {} format, {} bytes", 
             screenshot.image_format, 
             screenshot.image_data.len());
    
    Ok(screenshot.image_data)
}

pub async fn save_screenshot(client: &mut CompanionServiceClient, path: &str) -> Result<(), Box<dyn std::error::Error>> {
    let image_data = take_screenshot(client).await?;
    fs::write(path, image_data)?;
    println!("Screenshot saved to: {}", path);
    Ok(())
}

pub async fn verify_calibration_hit(
    client: &mut CompanionServiceClient,
    before_tap: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let filename = if before_tap {
        "calibration_before.png"
    } else {
        "calibration_after.png"
    };
    
    save_screenshot(client, filename).await?;
    
    // In a real automation, you would analyze the image here
    // to check if the targets changed from blue to green/red
    // For now, we just save the screenshots for manual inspection
    
    Ok(())
}