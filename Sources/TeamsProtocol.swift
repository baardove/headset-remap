import Foundation

/// Minimal local ASP handshake verified with the Evolve3 75 / Link 390.
/// This announces an idle USB client; it does not authenticate a Teams account.
enum TeamsProtocol {
    static let reportID: UInt32 = 0x9A
    static let reportLength = 64

    enum Message: UInt8 {
        case version = 0x00, capabilities = 0x10, locale = 0x20, idle = 0x30
    }

    static func report(_ message: Message, payload: [UInt8] = []) -> [UInt8]? {
        guard payload.count <= reportLength - 4 else { return nil }
        let header: [UInt8] = [UInt8(reportID), message.rawValue,
                              UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        return header + payload + Array(repeating: 0, count: reportLength - header.count - payload.count)
    }

    static func localePayload(at date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Len-GBD'yyyy-MM-dd'T'HH:mm:ss"
        return Array(formatter.string(from: date).utf8)
    }

    static func accepts(_ bytes: [UInt8], for message: Message) -> Bool {
        guard bytes.count >= 5, bytes[0] == UInt8(reportID), bytes[1] == message.rawValue,
              Int(bytes[2]) * 256 + Int(bytes[3]) >= 1,
              Int(bytes[2]) * 256 + Int(bytes[3]) <= bytes.count - 4 else { return false }
        switch message {
        case .version: return bytes[4] == 1
        case .capabilities: return bytes[4] != 0
        case .locale, .idle: return bytes[4] == 1
        }
    }
}
