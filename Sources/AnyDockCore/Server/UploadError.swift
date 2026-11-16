import Foundation

public enum UploadError: String, Error, Sendable {
    case badRequest = "Bad Request"
    case incompleteRequest = "Incomplete Request"
    case unauthorized = "Unauthorized"
    case lengthRequired = "Length Required"
    case payloadTooLarge = "Payload Too Large"
    case headersTooLarge = "Headers Too Large"
    case expectationFailed = "Expectation Failed"
    case unsupportedContentType = "Unsupported Content Type"
    case unsupportedTextType = "Unsupported Text Type"
    case invalidUTF8 = "Invalid UTF-8"
    case invalidUTF8Declaration = "Invalid UTF-8 Declaration"
    case invalidWebURL = "Invalid Web URL"
    case invalidFilename = "Invalid Filename"
    case filenameRequired = "Filename Required"
    case emptyContent = "Empty Content"
    case unsupportedImage = "Unsupported Image"
    case imageProcessingFailed = "Image Processing Failed"
    case invalidConfiguration = "Invalid Configuration"

    public var status: Int {
        switch self {
        case .badRequest, .incompleteRequest, .invalidFilename, .filenameRequired, .emptyContent, .invalidConfiguration: 400
        case .unauthorized: 401
        case .lengthRequired: 411
        case .payloadTooLarge: 413
        case .unsupportedContentType, .unsupportedTextType, .invalidUTF8, .invalidUTF8Declaration, .invalidWebURL, .unsupportedImage: 415
        case .expectationFailed: 417
        case .headersTooLarge: 431
        case .imageProcessingFailed: 500
        }
    }

    public var reason: String {
        rawValue
    }
}
