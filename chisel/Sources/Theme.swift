import AppKit
import SwiftUI

/// Палитра снята с иконки: тёмное дерево, песочная рамка, золото и оранжевый торец.
enum Theme {
    static let bg      = Color(red: 0.145, green: 0.086, blue: 0.051)
    static let panel   = Color(red: 0.204, green: 0.125, blue: 0.075)
    static let panelHi = Color(red: 0.271, green: 0.169, blue: 0.098)
    static let stroke  = Color(red: 0.376, green: 0.243, blue: 0.141)
    static let sand    = Color(red: 0.898, green: 0.745, blue: 0.486)
    static let gold    = Color(red: 1.000, green: 0.776, blue: 0.180)
    static let orange  = Color(red: 0.961, green: 0.569, blue: 0.118)
    static let text    = Color(red: 0.969, green: 0.945, blue: 0.914)
    static let textDim = Color(red: 0.706, green: 0.616, blue: 0.533)
    static let good    = Color(red: 0.478, green: 0.804, blue: 0.478)
    static let warn    = Color(red: 0.937, green: 0.510, blue: 0.318)

    static let nsBackground = NSColor(red: 0.145, green: 0.086, blue: 0.051, alpha: 1)
}

/// Фоновая картинка пустого окна.
/// Своя лежит в папке поддержки и ставится прямо из меню — пересборка не нужна.
/// Если её нет, берётся запасная из бандла.
enum AppAssets {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Chisel", isDirectory: true)
    }

    static var customBackgroundURL: URL {
        supportDirectory.appendingPathComponent("background.png")
    }

    static var customBackground: NSImage? {
        guard FileManager.default.fileExists(atPath: customBackgroundURL.path) else { return nil }
        return NSImage(contentsOf: customBackgroundURL)
    }

    static var bundledBackground: NSImage? {
        guard let url = Bundle.main.url(forResource: "background", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

/// Маленькая кнопка-переключатель для настроек, у которых два-четыре значения.
struct Pill: View {
    var title: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Theme.gold : Theme.panelHi)
                )
                .foregroundColor(active ? Color(red: 0.18, green: 0.10, blue: 0.04) : Theme.text)
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButton: View {
    var title: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(enabled ? Theme.orange : Theme.panelHi)
                )
                .foregroundColor(enabled ? Color(red: 0.16, green: 0.09, blue: 0.03) : Theme.textDim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct GhostButton: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
                .foregroundColor(enabled ? Theme.sand : Theme.textDim)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Строка «подпись — значение — ползунок».
struct SliderRow: View {
    var title: String
    var value: String
    var caption: String
    @Binding var position: Double
    var range: ClosedRange<Double> = 0...1
    /// Ноль — плавный ползунок, иначе шаг (у звука значений всего шесть).
    var step: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Theme.text)
            }
            slider
                .accentColor(Theme.gold)
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(Theme.textDim.opacity(0.8))
                .lineLimit(1)
        }
    }

    @ViewBuilder private var slider: some View {
        if step > 0 {
            Slider(value: $position, in: range, step: step)
        } else {
            Slider(value: $position, in: range)
        }
    }
}
