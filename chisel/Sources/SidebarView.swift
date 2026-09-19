import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.items) { item in
                        SidebarRow(item: item,
                                   selected: item.id == model.selection,
                                   busy: model.isConverting,
                                   selectable: !model.shareSettings,
                                   onSelect: { model.selection = item.id },
                                   onRemove: { model.remove(item.id) })
                    }
                }
                .padding(8)
            }
            Divider()
            Button(action: { model.pickFiles() }) {
                Text("+ Добавить")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.sand)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(width: ContentView.sidebarWidth)
        .background(Color.black.opacity(0.22))
    }
}

struct SidebarRow: View {
    var item: MediaItem
    var selected: Bool
    var busy: Bool
    /// Пока включено «Параметры на все видео», выбирать отдельный файл незачем:
    /// настройки всё равно общие, поэтому строки только показывают состояние очереди.
    var selectable: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(item.info.url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(statusColor)
            }
            Spacer(minLength: 2)
            if !busy {
                Button(action: onRemove) {
                    Text("×")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textDim)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture { if selectable { onSelect() } }
    }

    private var thumb: some View {
        Group {
            if let image = item.info.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.panel)
            }
        }
        .frame(width: 54, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var background: Color {
        if !selectable { return Theme.panelHi.opacity(0.35) }
        return selected ? Theme.panelHi : Color.clear
    }

    private var status: String {
        switch item.status {
        case .ready:   return "\(Fmt.bytes(item.info.fileSize)) → \(Fmt.bytes(item.estimatedBytes))"
        case .running: return "\(Int(item.progress * 100))%"
        case .done:    return "готово · \(Fmt.bytes(item.resultSize))"
        case .failed:  return "ошибка"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready:   return Theme.textDim
        case .running: return Theme.gold
        case .done:    return Theme.good
        case .failed:  return Theme.warn
        }
    }
}
