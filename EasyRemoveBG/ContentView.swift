import SwiftUI
import UniformTypeIdentifiers

// Helper struct for SwiftUI's fileExporter
struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.png]
    var image: NSImage

    init(image: NSImage) {
        self.image = image
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pngData)
    }
}

struct ContentView: View {
    @State private var originalImage: NSImage?
    @State private var processedImage: NSImage?
    @State private var isProcessing = false
    @State private var isTargeted = false
    @State private var errorMessage: String?
    
    // UI Feedback
    @State private var showCopyToast = false
    @State private var isExporting = false
    @State private var imageToExport: ImageDocument?
    @State private var isCapturing = false
    
    // Zoom & Pan State
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { windowSpace in
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerView
                    
                    ZStack {
                        if originalImage == nil && !isProcessing {
                            DropZoneView(isTargeted: $isTargeted) { image in
                                processImage(image)
                            }
                            .padding(40)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        } else {
                            mainPreviewView
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                
                // Floating Snapshot Button
                if !isCapturing && originalImage == nil && !isProcessing {
                    VStack {
                        Spacer()
                        Button(action: takeSnapshot) {
                            HStack(spacing: 10) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title3)
                                Text("Take Snapshot")
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(100)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 60)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                if isProcessing {
                    ScanningBeamView()
                        .transition(.opacity)
                }
                
                if showCopyToast {
                    toastView
                }
            }
            .opacity(isCapturing ? 0 : 1)
            .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .background(
                ZStack {
                    Button("") { pasteImage() }.keyboardShortcut("v", modifiers: .command)
                    Button("") { reset() }.keyboardShortcut(.escape, modifiers: [])
                    
                    // Zoom Shortcuts (Approximate container size from windowSpace)
                    Button("") { 
                        let containerSize = CGSize(width: windowSpace.size.width - 80, height: windowSpace.size.height - 150)
                        zoomIn(in: containerSize, imgSize: displayedImageSize(in: containerSize)) 
                    }.keyboardShortcut("+", modifiers: [])
                    
                    Button("") { 
                        let containerSize = CGSize(width: windowSpace.size.width - 80, height: windowSpace.size.height - 150)
                        zoomIn(in: containerSize, imgSize: displayedImageSize(in: containerSize)) 
                    }.keyboardShortcut("=", modifiers: [])
                    
                    Button("") { 
                        let containerSize = CGSize(width: windowSpace.size.width - 80, height: windowSpace.size.height - 150)
                        zoomOut(in: containerSize, imgSize: displayedImageSize(in: containerSize)) 
                    }.keyboardShortcut("-", modifiers: [])
                }
                .opacity(0)
            )
        }
        .frame(minWidth: 600, minHeight: 450)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isProcessing)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: originalImage)
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: imageToExport,
            contentType: .png,
            defaultFilename: "removed_background.png"
        ) { result in
            if case .failure(let error) = result {
                self.errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EasyRemoveBG")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(isProcessing ? "Scanning Image..." : (processedImage != nil ? "Background Removed • Double-click to reset" : "Local AI Removal"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    private var mainPreviewView: some View {
        VStack(spacing: 24) {
            GeometryReader { geometry in
                let containerSize = geometry.size
                let imgSize = displayedImageSize(in: containerSize)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(isTargeted ? 0.3 : 0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.accentColor.opacity(isTargeted ? 0.5 : 0), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    
                    ZStack {
                        if processedImage != nil {
                            CheckerboardTiledView()
                                .opacity(0.15)
                        }
                        
                        ZStack {
                            if let processed = processedImage {
                                Image(nsImage: processed)
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(scale)
                                    .offset(offset)
                            } else if let original = originalImage {
                                Image(nsImage: original)
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .opacity(isProcessing ? 0.7 : 1.0)
                                    .blur(radius: isProcessing ? 2 : 0)
                            }
                        }
                        .padding(24)
                        
                        if processedImage != nil {
                            ScrollGestureView(offset: $offset, onAction: {
                                offset = clampOffset(offset, containerSize: containerSize, imageSize: imgSize, scale: scale)
                            })
                        }
                        
                        if isTargeted {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                                Text("Drop to Start Over")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                let newScale = scale * delta
                                
                                // Smooth rubber-banding logic for zoom limits
                                if newScale < 1.0 {
                                    // Damping when zooming out below 1.0
                                    scale = 1.0 - (1.0 - newScale) * 0.2
                                } else if newScale > 15.0 {
                                    // Damping when zooming in above 15.0
                                    scale = 15.0 + (newScale - 15.0) * 0.2
                                } else {
                                    scale = newScale
                                }
                                
                                offset = clampOffset(offset, containerSize: containerSize, imageSize: imgSize, scale: scale)
                                lastOffset = offset
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    // Snap back to limits
                                    scale = min(max(scale, 1.0), 15.0)
                                    offset = clampOffset(offset, containerSize: containerSize, imageSize: imgSize, scale: scale)
                                    lastOffset = offset
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                let newOffset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                                offset = clampOffset(newOffset, containerSize: containerSize, imageSize: imgSize, scale: scale)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            resetZoom()
                        }
                    }
                    
                    if isProcessing {
                        ScanningBeamView()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(.horizontal, 40)
            
            HStack(spacing: 20) {
                if let processed = processedImage {
                    Button(action: reset) {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button(action: copyToClipboard) {
                        Label("Copy", systemImage: "doc.on.doc.fill")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("c", modifiers: .command)
                    
                    Button(action: {
                        self.imageToExport = ImageDocument(image: processed)
                        self.isExporting = true
                    }) {
                        Label("Save PNG", systemImage: "square.and.arrow.down.fill")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("s", modifiers: .command)
                } else {
                    HStack {
                        ProgressView().controlSize(.small).padding(.trailing, 8)
                        Text("AI is working its magic...").foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let droppedURL: URL? = {
                    if let url = item as? URL { return url }
                    if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                    return nil
                }()
                if let url = droppedURL, let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { processImage(image) }
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, error in
                if let image = image as? NSImage {
                    DispatchQueue.main.async { processImage(image) }
                }
            }
            return true
        }
        return false
    }
    
    private func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           let image = NSImage(contentsOf: url) {
            processImage(image)
            return
        }
        if let image = NSImage(pasteboard: pasteboard) {
            processImage(image)
        }
    }
    
    private func takeSnapshot() {
        NSApplication.shared.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let tempPath = NSTemporaryDirectory() + "easy_snapshot.png"
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = ["-i", tempPath]
            task.terminationHandler = { _ in
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    if let image = NSImage(contentsOfFile: tempPath) {
                        processImage(image)
                        try? FileManager.default.removeItem(atPath: tempPath)
                    }
                }
            }
            task.launch()
        }
    }
    
    private func processImage(_ image: NSImage) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            originalImage = image
            isProcessing = true
            processedImage = nil
            errorMessage = nil
            resetZoom()
        }
        Task {
            do {
                let result = try await BackgroundRemover.shared.removeBackground(from: image)
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        processedImage = result
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        withAnimation(.easeOut(duration: 0.2)) { isProcessing = false }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    originalImage = nil
                }
            }
        }
    }
    
    private func displayedImageSize(in containerSize: CGSize) -> CGSize {
        guard let image = originalImage else { return .zero }
        let usableWidth = containerSize.width - 48
        let usableHeight = containerSize.height - 48
        let imageRatio = image.size.width / image.size.height
        let usableRatio = usableWidth / usableHeight
        var size = CGSize.zero
        if imageRatio > usableRatio {
            size.width = usableWidth
            size.height = usableWidth / imageRatio
        } else {
            size.height = usableHeight
            size.width = usableHeight * imageRatio
        }
        return size
    }
    
    private func clampOffset(_ newOffset: CGSize, containerSize: CGSize, imageSize: CGSize, scale: CGFloat) -> CGSize {
        let usableWidth = containerSize.width - 48
        let usableHeight = containerSize.height - 48
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let maxX = max(0, (scaledWidth - usableWidth) / 2)
        let maxY = max(0, (scaledHeight - usableHeight) / 2)
        return CGSize(
            width: min(max(newOffset.width, -maxX), maxX),
            height: min(max(newOffset.height, -maxY), maxY)
        )
    }
    
    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    private func zoomIn(in containerSize: CGSize, imgSize: CGSize) {
        withAnimation(.smooth(duration: 0.3)) {
            let newScale = min(scale * 1.5, 15.0)
            scale = newScale
            lastScale = 1.0
            offset = clampOffset(offset, containerSize: containerSize, imageSize: imgSize, scale: scale)
            lastOffset = offset
        }
    }
    
    private func zoomOut(in containerSize: CGSize, imgSize: CGSize) {
        withAnimation(.smooth(duration: 0.3)) {
            let newScale = max(scale / 1.5, 1.0)
            scale = newScale
            lastScale = 1.0
            offset = clampOffset(offset, containerSize: containerSize, imageSize: imgSize, scale: scale)
            lastOffset = offset
        }
    }
    
    private func reset() {
        withAnimation(.smooth()) {
            originalImage = nil
            processedImage = nil
            isProcessing = false
            imageToExport = nil
            resetZoom()
        }
    }
    
    private func copyToClipboard() {
        guard let image = processedImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
            pasteboard.writeObjects([image])
            withAnimation(.spring()) { showCopyToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showCopyToast = false }
            }
        }
    }
    
    private var toastView: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Copied to Clipboard").fontWeight(.medium)
            }
            .padding(.vertical, 12).padding(.horizontal, 24)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(100)
    }
}

struct CheckerboardTiledView: View {
    var body: some View {
        Image(nsImage: createCheckerboardImage())
            .resizable(resizingMode: .tile)
    }
    private func createCheckerboardImage() -> NSImage {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.gray.set()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        NSBezierPath(rect: NSRect(x: 12, y: 12, width: 12, height: 12)).fill()
        image.unlockFocus()
        return image
    }
}

struct ScanningBeamView: View {
    @State private var scanPosition: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .accentColor.opacity(0.6), location: 0.5), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 120)
                    .offset(y: (scanPosition * (geometry.size.height + 240)) - 180)
                Rectangle()
                    .fill(Color.white).frame(height: 2)
                    .offset(y: (scanPosition * (geometry.size.height + 240)) - 120)
                    .shadow(color: .accentColor, radius: 20).shadow(color: .white, radius: 5)
            }
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    scanPosition = 1.0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ScrollGestureView: NSViewRepresentable {
    @Binding var offset: CGSize
    var onAction: () -> Void
    func makeNSView(context: Context) -> NSView { FlippedView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? FlippedView {
            view.offset = $offset
            view.onAction = onAction
        }
    }
    class FlippedView: NSView {
        var offset: Binding<CGSize>?
        var onAction: (() -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            DispatchQueue.main.async {
                self.offset?.wrappedValue.width += deltaX
                self.offset?.wrappedValue.height += deltaY
                self.onAction?()
            }
        }
    }
}
