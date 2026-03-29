import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ImageSaver {
    struct Options {
        let directory: URL
        let fileNamePrefix: String
        let timestampTemplate: String
    }

    enum SaveError: LocalizedError {
        case failedToCreateDirectory
        case failedToCreateDestination
        case failedToFinalize

        var errorDescription: String? {
            switch self {
            case .failedToCreateDirectory:
                return "Unable to create the screenshot directory."
            case .failedToCreateDestination:
                return "Unable to create the output PNG file."
            case .failedToFinalize:
                return "Unable to write the PNG data."
            }
        }
    }

    func save(image: CGImage, options: Options, date: Date = Date()) throws -> URL {
        let directory = try screenshotDirectory(from: options.directory)
        let filename = "\(sanitizedPrefix(options.fileNamePrefix))_\(timestampString(from: date, template: options.timestampTemplate)).png"
        let fileURL = directory.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SaveError.failedToCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SaveError.failedToFinalize
        }
        return fileURL
    }

    func save(image: CGImage, directory: URL) throws -> URL {
        try save(
            image: image,
            options: Options(
                directory: directory,
                fileNamePrefix: "screenshot",
                timestampTemplate: "yyyy-MM-dd_HH-mm-ss"
            )
        )
    }

    private func screenshotDirectory(from directory: URL) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw SaveError.failedToCreateDirectory
        }
    }

    private func timestampString(from date: Date, template: String) -> String {
        let formatter = Self.makeTimestampFormatter(template: template)
        return formatter.string(from: date)
    }

    private func sanitizedPrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(
            of: #"[\\/:*?"<>|]+"#,
            with: "-",
            options: .regularExpression
        )
        return sanitized.isEmpty ? "screenshot" : sanitized
    }

    private static func makeTimestampFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = template.isEmpty ? "yyyy-MM-dd_HH-mm-ss" : template
        return formatter
    }
}
