// Where the intel API lives and how to authenticate: the URL in UserDefaults, the token in the Keychain.

import Foundation
import Security

public struct ConnectionSettings: Sendable, Equatable {
    public static let defaultServer = URL(string: "http://127.0.0.1:8765")!

    public var serverURL: URL
    public var token: String

    public init(serverURL: URL = ConnectionSettings.defaultServer, token: String = "") {
        self.serverURL = serverURL
        self.token = token
    }

    public var IsComplete: Bool { !token.isEmpty }

    public static func Load() -> ConnectionSettings {
        let stored = UserDefaults.standard.string(forKey: serverKey).flatMap(URL.init(string:))
        return ConnectionSettings(serverURL: stored ?? defaultServer, token: Keychain.Read(account: tokenAccount) ?? "")
    }

    public func Save() throws {
        UserDefaults.standard.set(serverURL.absoluteString, forKey: Self.serverKey)
        try Keychain.Write(token, account: Self.tokenAccount)
    }

    /// The token of the intel installed on this Mac, via `intel api token` (nil if intel isn't found).
    public static func TokenFromLocalIntel() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/intel", "\(home)/.local/bin/intel", "/usr/local/bin/intel"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["api", "token"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let token = text.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return token?.isEmpty == false ? token : nil
    }

    private static let serverKey = "serverURL"
    private static let tokenAccount = "api-token"
}

/// Minimal wrapper over the login Keychain for this app's own items.
public enum Keychain {
    static let service = "local.intel.gui"

    public static func Read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func Write(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't save the token in the Keychain (\(status))"])
        }
    }
}
