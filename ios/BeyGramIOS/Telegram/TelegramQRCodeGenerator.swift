import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Builds a QR bitmap locally. The tg://login token must not be logged,
/// stored in analytics, or uploaded to any QR-rendering service.
enum TelegramQRCodeGenerator {
    static func image(for link: String) -> UIImage? {
        guard link.hasPrefix("tg://login?token=") else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: image)
    }
}
