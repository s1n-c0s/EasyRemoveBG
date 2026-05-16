import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BackgroundRemoverError: Error, LocalizedError {
    case failedToCreateCGImage
    case failedToGenerateMask
    case failedToApplyMask
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateCGImage: return "Could not initialize image."
        case .failedToGenerateMask: return "Background removal failed: No subject detected."
        case .failedToApplyMask: return "Failed to render the transparent image."
        }
    }
}

class BackgroundRemover {
    static let shared = BackgroundRemover()
    
    // Shared CIContext is high-performance and memory-efficient
    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: NSNull(), // Disable color management for speed and accuracy
        .highQualityDownsample: true,
        .cacheIntermediates: false // Don't cache intermediate images to save memory
    ])
    
    private init() {}
    
    func removeBackground(from image: NSImage) async throws -> NSImage {
        // Use autoreleasepool to ensure high-res image buffers are released immediately
        return try autoreleasepool {
            // 1. Get CGImage
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw BackgroundRemoverError.failedToCreateCGImage
            }
            
            // 2. Load CIImage with color management disabled
            let sourceCI = CIImage(cgImage: cgImage, options: [CIImageOption.colorSpace: NSNull()])
            
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            try handler.perform([request])
            
            guard let result = request.results?.first else {
                throw BackgroundRemoverError.failedToGenerateMask
            }
            
            // 3. Generate Native AI Mask
            let maskPixelBuffer = try result.generateMask(forInstances: result.allInstances)
            var maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
            
            // 4. Scale and Align
            let scaleX = sourceCI.extent.width / maskCI.extent.width
            let scaleY = sourceCI.extent.height / maskCI.extent.height
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: sourceCI.extent)
            
            // 5. MASK EROSION (Professional finish)
            let morphologyFilter = CIFilter.morphologyMinimum()
            morphologyFilter.inputImage = maskCI
            morphologyFilter.radius = 1.5 
            
            if let erodedMask = morphologyFilter.outputImage {
                maskCI = erodedMask
            }
            
            // 6. SOFTEN EDGE
            maskCI = maskCI.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.0])
                .cropped(to: sourceCI.extent)
            
            // 7. Blend
            guard let filter = CIFilter(name: "CIBlendWithMask") else {
                throw BackgroundRemoverError.failedToApplyMask
            }
            filter.setValue(sourceCI, forKey: kCIInputImageKey)
            filter.setValue(maskCI, forKey: kCIInputMaskImageKey)
            filter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            
            guard let outputCI = filter.outputImage else {
                throw BackgroundRemoverError.failedToApplyMask
            }
            
            // 8. Render final result directly to CGImage
            guard let finalCG = context.createCGImage(outputCI, from: sourceCI.extent) else {
                throw BackgroundRemoverError.failedToApplyMask
            }
            
            return NSImage(cgImage: finalCG, size: image.size)
        }
    }
}
