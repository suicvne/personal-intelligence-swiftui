// Settings: where intel's API is and the token to use (kept in the Keychain).

import IntelKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var token = ""
    @State private var check: String?

    var body: some View {
        Form {
            Section {
                TextField("Server", text: $server, prompt: Text(ConnectionSettings.defaultServer.absoluteString))
                SecureField("Token", text: $token)
                HStack {
                    Button("Use the token of the intel on this Mac") {
                        if let local = ConnectionSettings.TokenFromLocalIntel() {
                            token = local
                            check = "Token read from `intel api token`."
                        } else {
                            check = "Couldn't run `intel api token`. Run it in a terminal and paste the token here."
                        }
                    }
                    Button("Test connection", action: Test)
                }
                if let check { Text(check).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                Text("The background service serves the API on 127.0.0.1:8765. Get the token with `intel api token`.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try model.Save(Current)
                        dismiss()
                    } catch {
                        check = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || URL(string: server) == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
        .onAppear {
            server = model.settings.serverURL.absoluteString
            token = model.settings.token
        }
    }

    private var Current: ConnectionSettings {
        ConnectionSettings(serverURL: URL(string: server) ?? ConnectionSettings.defaultServer, token: token)
    }

    private func Test() {
        let client = IntelClient(baseURL: Current.serverURL, token: Current.token)
        check = "Testing…"
        Task {
            do {
                let status = try await client.Status()
                check = "Connected: intel \(status.version), \(status.sources.count) sources, \(status.pendingProposals) proposals waiting."
            } catch {
                check = error.localizedDescription
            }
        }
    }
}
