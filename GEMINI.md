# EasyRemoveBG - MacOS Native Background Removal

## Project Overview
EasyRemoveBG is a professional-grade, native macOS application for local image background removal. It leverages Apple's **Vision framework** and **Neural Engine** for high-performance inference without sending data to the cloud. The app features an immersive, unified UI with real-time feedback and advanced image inspection tools.

### Key Technologies
- **Language**: Swift 5.10+
- **Framework**: SwiftUI (minimum target: macOS 14.0 Sonoma)
- **Engine**: Apple Vision API (`VNGenerateForegroundInstanceMaskRequest`)
- **Rendering**: Core Image (CIContext) with color-neutral processing (`NSNull` working color space)
- **Hardware**: Fully optimized for Apple Silicon (Neural Engine/ANE)

## Key Features
- **High-Fidelity AI Removal**: Native Apple algorithm enhanced with a professional edge pipeline:
    - **Edge-Preserving Upsampling**: Uses the source image as a high-res guide for the AI mask.
    - **Noise Reduction**: Integrated median filtering to eliminate edge jitter and artifacts.
    - **Sharp Anti-Aliasing**: Advanced alpha-ramp control for crisp, well-defined boundaries.
- **Unified UX**: No screen switching; drop an image and see it process instantly in a high-res preview.
- **Immersive Visuals**: Full-screen scanning beam animation and glassmorphism (VisualEffectView).
- **Advanced Inspection**: 
    - **Rubber-Band Zoom**: Precise magnification between 1.0x and 15x with professional visual resistance and spring-back.
    - **Fluid Panning**: Supports standard Drag AND native two-finger trackpad scrolling.
    - **Strict Bounded Navigation**: Pan area is locked to the subject (0% margin) to prevent losing the image.
    - **Quick Reset**: Double-click to instantly reset zoom and position.
- **Productivity Workflow**: 
    - **Global Drag & Drop**: Drop a new image at any time to start over instantly.
    - **Snapshot to Remove**: Dedicated floating action button hides the app for a clean screen capture.
    - **Lossless Export**: PNG preservation for Photoshop, Slack, etc.

## Keyboard Shortcuts & Power Actions
- **Cmd + V**: Paste to remove (Intelligent loading of high-res files from Finder).
- **Cmd + C**: Copy result to clipboard.
- **Cmd + N**: Take screen snapshot.
- **Esc**: Reset to the landing screen.
- **+ / =**: Zoom In.
- **-**: Zoom Out.
- **Double-Click**: Reset view.

## Performance & Efficiency
- **Energy Optimized**: Uses a static tiled checkerboard background instead of heavy canvas drawing to reduce GPU impact.
- **Memory Managed**: Utilizes `autoreleasepool` and shared `CIContext` to ensure large image buffers (4K/8K) are cleared immediately.
- **Zero Latency**: Instant AI reveal with a high-speed (0.8s) beam overlay.

## Building and Running
1. Open the project in **Xcode 15.0** or newer.
2. **Requirements**: Set the Deployment Target to **macOS 14.0** or newer.
3. **App Sandbox**: If enabled, ensure `User Selected File` is set to `Read/Write` in Signing & Capabilities.
4. **Command Line Build**:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme EasyRemoveBG -configuration Release -derivedDataPath ./build build
   ```
5. **App Icon**: The project uses a 1024x1024 "Magic Frame" PNG for the `AppIcon.appiconset`.

## Development Conventions
- **Local-First**: All processing must happen on-device. No network requests. (Verified: No `URLSession` or network sockets in source).
- **Color Accuracy**: Utilize native Core Image color management (avoid `NSNull` working color space) to correctly interpret gamma and HDR metadata, especially for HEIC and P3 images. Always tag the final output `CGImage` with the source image's color space to preserve fidelity.
- **Input Priority**: Prioritize `NSURL` objects over raw `NSImage` objects on the pasteboard to ensure high-res file loading.
- **Project Location**: Currently maintained in `/Users/mac/Documents/macapp/EasyRemoveBG/`.
