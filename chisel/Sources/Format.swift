import Foundation

/// Единицы как в Finder — десятичные (1 МБ = 1 000 000 байт),
/// иначе цифра в приложении не сойдётся с тем, что видно в Finder.
enum Fmt {
    static func bytes(_ v: Int64) -> String {
        let d = Double(max(0, v))
        if d >= 1_000_000_000 { return String(format: "%.2f ГБ", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1f МБ", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0f КБ", d / 1_000) }
        return "\(max(0, v)) Б"
    }

    static func bitrate(_ bps: Double) -> String {
        guard bps.isFinite, bps > 0 else { return "—" }
        if bps >= 1_000_000 { return String(format: "%.1f Мбит/с", bps / 1_000_000) }
        return String(format: "%.0f кбит/с", bps / 1_000)
    }

    static func duration(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "—" }
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    static func fps(_ v: Double) -> String {
        guard v.isFinite, v > 0 else { return "—" }
        return String(format: v.rounded() == v ? "%.0f к/с" : "%.2f к/с", v)
    }

    static func signedPercent(_ ratio: Double) -> String {
        guard ratio.isFinite else { return "—" }
        let p = (ratio - 1.0) * 100.0
        if abs(p) < 0.5 { return "без изменений" }
        return String(format: p < 0 ? "−%.0f%%" : "+%.0f%%", abs(p))
    }
}
