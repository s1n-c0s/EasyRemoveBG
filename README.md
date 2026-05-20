# EasyRemoveBG 🚀
Professional-grade, native macOS application for local image background removal.

## 🌟 Key Features
- **Pro-Grade AI Removal**: High-fidelity edge-preserving upsampling and noise reduction for clean, sharp cutouts.
- **Unified UX**: Drag & drop interface with real-time feedback and high-speed processing beam.
- **Advanced Inspection**: Rubber-band zoom (1x-15x) and fluid panning for pixel-perfect review.
- **Performance**: Fully optimized for Apple Silicon (ANE) with zero-latency inference.

## 🛠 Building
Requires **Xcode 15.0+** and **macOS 14.0+**.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme EasyRemoveBG -configuration Release -derivedDataPath ./build build
```

## 🔒 Security & Privacy
- **100% Local**: No network requests or data collection.
- **Sandboxed**: (Optional) Can be configured for App Sandbox.

## 📜 Documentation
See [GEMINI.md](./GEMINI.md) for detailed development guidelines and technical specifications.
