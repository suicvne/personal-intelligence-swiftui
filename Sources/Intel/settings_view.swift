// Settings: where intel's API is, the token to use (kept in the Keychain), the model intel uses, and the
// persona its answers are written and read aloud in.

import IntelKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var token = ""
    @State private var check: String?
    @State private var models: LlmModelsView?
    @State private var modelProblem: String?
    /// The model to use; "" means the one in intel's config.
    @State private var chosenModel = ""
    @State private var personas: PersonasView?
    @State private var personaProblem: String?
    /// The persona to use; nil means intel's config.
    @State private var chosenPersona: Int?

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
            Section {
                ModelPicker()
            } footer: {
                Text("Every LLM task uses this model: answers, extraction and briefs. The background service switches at its next cycle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PersonaSection(client: CurrentClient, personas: $personas, chosen: $chosenPersona, problem: personaProblem)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await SaveAll() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.isEmpty || URL(string: server) == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
        .task {
            server = model.settings.serverURL.absoluteString
            token = model.settings.token
            await LoadModels()
            await LoadPersonas()
        }
    }

    @ViewBuilder
    private func ModelPicker() -> some View {
        if let models, models.enabled {
            Picker("Model", selection: $chosenModel) {
                Text("From intel's config (\(models.configured ?? "?"))").tag("")
                Divider()
                ForEach(ModelOptions(models), id: \.self) { Text($0).tag($0) }
            }
            if let error = models.error {
                Text("Couldn't list the endpoint's models: \(error)").font(.caption).foregroundStyle(.orange)
            }
        } else if models != nil {
            Text("The LLM is turned off in intel's config ([llm] enabled = false).").foregroundStyle(.secondary)
        } else if let modelProblem {
            Text(modelProblem).font(.caption).foregroundStyle(.secondary)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// The endpoint's models, plus the chosen one if the endpoint didn't list it (so the picker can show it).
    private func ModelOptions(_ models: LlmModelsView) -> [String] {
        guard let chosen = models.chosen, !models.available.contains(chosen) else { return models.available }
        return [chosen] + models.available
    }

    private var Current: ConnectionSettings {
        ConnectionSettings(serverURL: URL(string: server) ?? ConnectionSettings.defaultServer, token: token)
    }

    private var CurrentClient: IntelClient { IntelClient(baseURL: Current.serverURL, token: Current.token) }

    private func Test() {
        check = "Testing…"
        Task {
            do {
                let status = try await CurrentClient.Status()
                check = "Connected: intel \(status.version), \(status.sources.count) sources, \(status.pendingProposals) proposals waiting."
                await LoadModels()
                await LoadPersonas()
            } catch {
                check = error.localizedDescription
            }
        }
    }

    private func LoadModels() async {
        guard Current.IsComplete else {
            modelProblem = "Connect to intel to choose its model."
            return
        }
        do {
            let loaded = try await CurrentClient.LlmModels()
            models = loaded
            chosenModel = loaded.chosen ?? ""
            modelProblem = nil
        } catch {
            models = nil
            modelProblem = "Couldn't load intel's models: \(error.localizedDescription)"
        }
    }

    private func LoadPersonas() async {
        guard Current.IsComplete else {
            personaProblem = "Connect to intel to choose a persona."
            return
        }
        do {
            let loaded = try await CurrentClient.Personas()
            personas = loaded
            chosenPersona = loaded.chosen
            personaProblem = nil
        } catch {
            personas = nil
            personaProblem = "Couldn't load intel's personas: \(error.localizedDescription)"
        }
    }

    private func SaveAll() async {
        do {
            try model.Save(Current)
            if let models, models.enabled, chosenModel != (models.chosen ?? "") {
                _ = try await CurrentClient.ChooseLlmModel(chosenModel.isEmpty ? nil : chosenModel)
                model.RequestRefresh()      // the status footer names the model
            }
            if let personas, chosenPersona != personas.chosen {
                _ = try await CurrentClient.ChoosePersona(chosenPersona)
            }
            dismiss()
        } catch {
            check = error.localizedDescription
        }
    }
}
