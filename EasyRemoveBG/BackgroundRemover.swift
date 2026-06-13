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
            
            // 2. Load CIImage with full color management
            let sourceCI = CIImage(cgImage: cgImage)
            
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
            morphologyFilter.radius = 0.6
            
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
            processedMask = processedMask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            
            let contrastFilter = CIFilter.colorControls()
            contrastFilter.inputImage = processedMask
            contrastFilter.contrast = 1.4
            if let finalizedMask = contrastFilter.outputImage {
                processedMask = finalizedMask
            }
            processedMask = processedMask.cropped(to: sourceCI.extent)
            
            // 8. Render the finalized mask to a grayscale CGImage
            guard let maskCG = context.createCGImage(processedMask, from: sourceCI.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()) else {
                throw BackgroundRemoverError.failedToApplyMask
            }
            
            // 9. Use CGContext to perform the final composition
            // This ensures the original pixels are drawn directly without any CI processing
            let width = cgImage.width
            let height = cgImage.height
            let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let bitsPerComponent = cgImage.bitsPerComponent
            let bitmapInfo = cgImage.bitmapInfo.isEmpty ? CGImageAlphaInfo.premultipliedLast.rawValue : cgImage.bitmapInfo.rawValue
            
            guard let renderContext = CGContext(data: nil,
                                                width: width,
                                                height: height,
                                                bitsPerComponent: bitsPerComponent,
                                                bytesPerRow: 0,
                                                space: colorSpace,
                                                bitmapInfo: bitmapInfo) else {
                // Fallback to standard if specific bits/info fail
                guard let fallbackContext = CGContext(data: nil,
                                                    width: width,
                                                    height: height,
                                                    bitsPerComponent: 8,
                                                    bytesPerRow: 0,
                                                    space: colorSpace,
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw BackgroundRemoverError.failedToApplyMask
                }
                return try performComposition(on: fallbackContext, with: cgImage, mask: maskCG, size: image.size)
            }
            
            return try performComposition(on: renderContext, with: cgImage, mask: maskCG, size: image.size)
        }
    }
    
    private func performComposition(on renderContext: CGContext, with cgImage: CGImage, mask: CGImage, size: NSSize) throws -> NSImage {
        let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        renderContext.clip(to: rect, mask: mask)
        renderContext.draw(cgImage, in: rect)
        
        guard let finalCG = renderContext.makeImage() else {
            throw BackgroundRemoverError.failedToApplyMask
        }
        
        return NSImage(cgImage: finalCG, size: size)
    }
}
