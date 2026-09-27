import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

extension LinkInvitation {
    /// Reads the first invitation among the QR codes in a picture, such as a photo of the Hub's screen.
    public init(image: CGImage) throws {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let codes = (request.results ?? []).compactMap(\.payloadStringValue)
        guard let invitation = codes.lazy.compactMap({ try? LinkInvitation(text: $0) }).first else {
            throw LinkError(codes.isEmpty ? "No QR code was found in the picture." : "The QR code is not a Noodle Hub invitation.")
        }
        self = invitation
    }

    /// The QR code of its link, a pixel a module, for a device to scan.
    public func qrCode() -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url().absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
