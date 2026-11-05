import Foundation

/// The kind of a media message in a transcript placeholder (MATRIX-113).
public enum MessageTranscriptMediaKind: Equatable, Sendable {
    case image
    case video
    case audio
    case file
}

/// One selected message, as the transcript copy reads it (MATRIX-113,
/// M2-B6, D-2).
///
/// Plain values only, so the transcript rules run in unit tests. `Core`
/// builds a line from an SDK event
/// (`MessageTranscriptLine(event:msg:displayIndex:)`).
public struct MessageTranscriptLine: Equatable, Sendable {
    /// What the message shows, reduced to what a plain-text line can carry.
    public enum Body: Equatable, Sendable {
        /// Text, notice, emote, and location bodies: the plain-text body.
        case text(String)
        /// An image, video, audio, or file message.
        case media(MessageTranscriptMediaKind, filename: String, caption: String?)
        /// A gallery message, with its body text.
        case gallery(String)
        /// A sticker, with its body text.
        case sticker(String)
        /// A poll, with its question.
        case poll(question: String)
        /// A redacted (deleted) message.
        case redacted
        /// A message the client could not decrypt.
        case unableToDecrypt
        /// Custom events, live locations, and other content with no text.
        case unsupported
    }

    /// The row's index in the display order: 0 is the newest message. The
    /// transcript lists the highest index first, so it reads oldest first.
    public var displayIndex: Int
    /// The sender's display name, or the user ID when there is no name.
    public var sender: String
    /// When the message was sent.
    public var date: Date
    public var body: Body

    public init(displayIndex: Int, sender: String, date: Date, body: Body) {
        self.displayIndex = displayIndex
        self.sender = sender
        self.date = date
        self.body = body
    }

    /// The name a transcript line shows for a sender: the display name from a
    /// loaded profile, else the user ID. The row header uses the same rule.
    ///
    /// - Parameters:
    ///   - userId: The sender's Matrix user ID.
    ///   - profile: The sender's profile, as the timeline item reports it.
    public static func senderName(userId: String, profile: ProfileDetails) -> String {
        guard case let .ready(displayName?, _, _) = profile else { return userId }
        return displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? userId : displayName
    }
}

/// Builds the plain-text transcript that ⌘C copies from a message selection
/// (MATRIX-113, M2-B6, D-2).
///
/// One line per message, oldest first: `Sender, HH:MM: body`. The time is the
/// 24-hour clock the timeline's timestamp column shows. A body with line
/// breaks keeps them, so a multi-line message spans more than one line.
/// Messages without text get a bracketed placeholder:
/// - media: `[Image: photo.jpg]`, `[Video: …]`, `[Audio: …]`, `[File: …]`,
///   then the caption after a space when there is one;
/// - `[Gallery: body]`, `[Sticker: body]`, `[Poll: question]`;
/// - `[Message deleted]`, `[Unable to decrypt]`, `[Unsupported message]`.
///
/// Usage:
/// ```swift
/// let text = MessageTranscript.text(for: lines)
/// ```
public enum MessageTranscript {
    /// The transcript of `lines`, in timeline order (oldest first).
    ///
    /// - Parameters:
    ///   - lines: The selected messages, in any order.
    ///   - timeZone: The time zone of the times. The user's own by default.
    /// - Returns: The lines joined by a line break, with no trailing break.
    public static func text(for lines: [MessageTranscriptLine], timeZone: TimeZone = .current) -> String {
        let formatter = timeFormatter(timeZone: timeZone)
        return lines
            .sorted { $0.displayIndex > $1.displayIndex }
            .map { line(for: $0, formatter: formatter) }
            .joined(separator: "\n")
    }

    /// The text of one message body, without the sender and the time.
    public static func bodyText(of body: MessageTranscriptLine.Body) -> String {
        switch body {
        case let .text(text):
            return text
        case let .media(kind, filename, caption):
            let placeholder = filename.isEmpty
                ? "[\(mediaLabel(kind))]"
                : "[\(mediaLabel(kind)): \(filename)]"
            guard let caption, !caption.isEmpty else { return placeholder }
            return "\(placeholder) \(caption)"
        case let .gallery(text):
            return "[\(String(localized: "Gallery")): \(text)]"
        case let .sticker(text):
            return "[\(String(localized: "Sticker")): \(text)]"
        case let .poll(question):
            return "[\(String(localized: "Poll")): \(question)]"
        case .redacted:
            return "[\(String(localized: "Message deleted"))]"
        case .unableToDecrypt:
            return "[\(String(localized: "Unable to decrypt"))]"
        case .unsupported:
            return "[\(String(localized: "Unsupported message"))]"
        }
    }

    static func line(for line: MessageTranscriptLine, formatter: DateFormatter) -> String {
        "\(line.sender), \(formatter.string(from: line.date)): \(bodyText(of: line.body))"
    }

    /// `HH:mm` with a fixed locale, so the user's 12-hour setting or calendar
    /// does not change the transcript format.
    static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func mediaLabel(_ kind: MessageTranscriptMediaKind) -> String {
        switch kind {
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .file: String(localized: "File")
        }
    }
}
