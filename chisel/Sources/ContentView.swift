import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    static let paneWidth: CGFloat = 480
    static let sidebarWidth: CGFloat = 236

    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
            if model.isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.gold, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        // Ширина фиксирована: окно компактное и не растягивается.
        // Боковой список добавляет к ней свою полосу, когда файлов несколько.
        .frame(width: model.items.count > 1 ? ContentView.paneWidth + ContentView.sidebarWidth
                                            : ContentView.paneWidth)
        .onDrop(of: [UTType.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty {
            EmptyStateView(model: model)
        } else if model.items.count > 1 {
            HStack(spacing: 0) {
                SidebarView(model: model)
                DetailView(model: model)
                    .frame(width: ContentView.paneWidth)
            }
        } else {
            DetailView(model: model)
        }
    }
}

struct EmptyStateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if let background = AppAssets.background {
                Image(nsImage: background)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 168, height: 168)
                    .opacity(0.6)
                    .padding(.bottom, 6)
            }
            Text("Выберите видео или перетащите его сюда.")
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
            Text("⌘V вставит файл из буфера обмена")
                .font(.system(size: 11))
                .foregroundColor(Theme.textDim)
            if model.isLoading {
                Text("Читаю файл…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.sand)
                    .padding(.top, 6)
            }
            if !model.loadError.isEmpty {
                Text(model.loadError)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.warn)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .contentShape(Rectangle())
        .onTapGesture { model.pickFiles() }
    }
}
