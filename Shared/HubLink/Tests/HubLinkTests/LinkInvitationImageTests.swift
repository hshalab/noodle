import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
@testable import HubLink
import XCTest

final class LinkInvitationImageTests: XCTestCase {
    private let invitation = LinkInvitation(
        hubName: "Mac mini", hubKey: LinkIdentity().publicKey,
        endpoints: [LinkEndpoint(host: "Mac-mini.local", port: 38_415), LinkEndpoint(host: "192.168.1.20", port: 38_415)],
        userName: "Ada", joinKey: LinkIdentity().privateKey.rawRepresentation, expires: Date(timeIntervalSince1970: 1_790_000_000))

    /// The QR code as the Hub draws it, scaled up and placed on a larger white picture.
    private func picture(of text: String) throws -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let code = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let canvas = CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -80, dy: -80))
        let image = code.transformed(by: .identity).composited(over: canvas)
        return try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
    }

    func testInvitationsAreReadFromAPictureOfTheirQRCode() throws {
        XCTAssertEqual(try LinkInvitation(image: try picture(of: invitation.url().absoluteString)), invitation)
    }

    func testTheInvitationsOwnQRCodeReadsBack() throws {
        let code = try XCTUnwrap(invitation.qrCode())
        let scaled = CIImage(cgImage: code).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let image = try XCTUnwrap(CIContext().createCGImage(scaled, from: scaled.extent))
        XCTAssertEqual(try LinkInvitation(image: image), invitation)
    }

    func testInvitationsAreReadFromACameraFrame() throws {
        let image = CIImage(cgImage: try picture(of: invitation.url().absoluteString))
        var frame: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &frame)
        let buffer = try XCTUnwrap(frame)
        CIContext().render(image, to: buffer)
        XCTAssertEqual(try LinkInvitation(frame: buffer), invitation)
    }

    func testPicturesWithoutAnInvitationSaySo() throws {
        XCTAssertThrowsError(try LinkInvitation(image: try picture(of: "https://example.com")))
        let blank = try XCTUnwrap(CIContext().createCGImage(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)),
                                                             from: CGRect(x: 0, y: 0, width: 200, height: 200)))
        XCTAssertThrowsError(try LinkInvitation(image: blank))
    }
}
