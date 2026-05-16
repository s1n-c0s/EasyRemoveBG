import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    var onDrop: (NSImage) -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
                
                Image(systemName: isTargeted ? "photo.on.rectangle.angled" : "photo.badge.plus")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
                    .symbolEffect(.bounce, value: isTargeted)
            }
            
            VStack(spacing: 8) {
                Text("Drop or Paste an image")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                
                Text("PNG, JPG, or Cmd + V")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [10, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(isTargeted ? Color.accentColor.opacity(0.03) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isTargeted)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    let droppedURL: URL? = {
                        if let url = item as? URL { return url }
                        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                        return nil
                    }()
                    
                    if let url = droppedURL, let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            onDrop(image)
                        }
                    }
                }
                return true
            }
            
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, error in
                    if let image = image as? NSImage {
                        DispatchQueue.main.async {
                            onDrop(image)
                        }
                    }
                }
                return true
            }
            return false
        }
    }
}
