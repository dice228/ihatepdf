import Foundation

/// Вся математика «сколько будет весить» вынесена сюда отдельно от UI:
/// её считают и слайдеры (в реальном времени), и кодировщик (перед запуском).
enum Estimator {

    /// Размер = (битрейт видео + битрейт звука) × длительность ÷ 8,
    /// плюс накладные расходы контейнера MP4 (заголовки, индекс moov).
    static func estimatedBytes(videoBps: Double, audioBps: Double, seconds: Double, frames: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let payload = (videoBps + audioBps) * seconds / 8.0
        let moov = 1_800.0 + frames * 12.0     // таблицы сэмплов растут с числом кадров
        return Int64((payload * 1.003 + moov).rounded())
    }

    /// H.264 в 4:2:0 требует чётных сторон.
    static func even(_ v: Int) -> Int { max(2, v - (v % 2)) }

    static func targetSize(sourceWidth: Int, sourceHeight: Int, scale: Double) -> (w: Int, h: Int) {
        let s = min(max(scale, 0.05), 1.0)
        return (even(Int((Double(sourceWidth) * s).rounded())),
                even(Int((Double(sourceHeight) * s).rounded())))
    }

}
