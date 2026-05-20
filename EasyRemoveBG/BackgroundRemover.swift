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
            let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
            
            // 4. High-Quality Edge-Preserving Upsample
            // Instead of simple scaling, we use the original image as a guide to upscale 
            // the low-res AI mask. This ensures the mask edges align perfectly with 
            // the actual pixel boundaries of the subject.
            let upsampleFilter = CIFilter.edgePreserveUpsample()
            upsampleFilter.inputImage = sourceCI // High-res Guide
            upsampleFilter.smallImage = maskCI  // Low-res Mask
            upsampleFilter.lumaSigma = 0.15
            upsampleFilter.spatialSigma = 3.0
            
            var processedMask = upsampleFilter.outputImage ?? maskCI.transformed(by: CGAffineTransform(
                scaleX: sourceCI.extent.width / maskCI.extent.width,
                y: sourceCI.extent.height / maskCI.extent.height
            ))
            processedMask = processedMask.cropped(to: sourceCI.extent)
            
            // 5. MASK EROSION (Eliminate background bleeding/halos)
            let morphologyFilter = CIFilter.morphologyMinimum()
            morphologyFilter.inputImage = processedMask
            morphologyFilter.radius = 0.6 // Reduced from 0.8 to preserve more edge detail
            
            if let erodedMask = morphologyFilter.outputImage {
                processedMask = erodedMask
            }
            
            // 6. NOISE REDUCTION (Remove jitter/artifacts)
            let medianFilter = CIFilter.median()
            medianFilter.inputImage = processedMask
            if let denoisedMask = medianFilter.outputImage {
                processedMask = denoisedMask
            }
            
            // 7. SHARP ANTI-ALIASING
            // By using a smaller blur (0.8) and higher contrast (1.4), we create 
            // a much sharper transition that still looks smooth on high-res displays.
            processedMask = processedMask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            
            let contrastFilter = CIFilter.colorControls()
            contrastFilter.inputImage = processedMask
            contrastFilter.contrast = 1.4 // Higher contrast for a sharper "cut"
            if let finalizedMask = contrastFilter.outputImage {
                processedMask = finalizedMask
            }
            processedMask = processedMask.cropped(to: sourceCI.extent)
            
            // 8. Blend
            guard let filter = CIFilter(name: "CIBlendWithMask") else {
                throw BackgroundRemoverError.failedToApplyMask
            }
            filter.setValue(sourceCI, forKey: kCIInputImageKey)
            filter.setValue(processedMask, forKey: kCIInputMaskImageKey)
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
