import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var keyDraft = AppSettings.shared.apiKey
    @State private var models: [String] = []
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        Form {
            connection
            modelSection
            appearance
            conversation
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 560)
        .task { if settings.hasAPIKey { await loadModels() } }
    }

    private var connection: some View {
        Section {
            HStack(spacing: 8) {
                SecureField("Cole sua API key do OpenCode Go", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Salvar", action: saveKey)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty
                              || keyDraft == settings.apiKey)
            }
            HStack(spacing: 8) {
                Button("Testar chave") { Task { await testKey() } }
                    .disabled(busy || !settings.hasAPIKey)
                Button("Remover") {
                    settings.apiKey = ""
                    keyDraft = ""
                    note = "Chave removida."
                }
                .disabled(!settings.hasAPIKey)
                if busy { ProgressView().controlSize(.small) }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Conexão")
        } footer: {
            Text("Guardada em \(pretty(Secrets.location)) — fora do repositório, "
                 + "legível só por você (0600).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section {
            if models.isEmpty {
                TextField("Modelo", text: $settings.model)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Modelo", selection: $settings.model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            }
            Button("Buscar modelos disponíveis") { Task { await loadModels() } }
                .disabled(!settings.hasAPIKey || busy)
        } header: {
            Text("Modelo")
        } footer: {
            Text("O Dino responde em balões curtos, então modelos rápidos funcionam "
                 + "melhor que os pesados.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        Section {
            HStack {
                Text("Tamanho do Dino")
                Slider(value: $settings.spriteScale, in: 0.6...1.8, step: 0.05)
                Text(String(format: "%.0f%%", settings.spriteScale * 100))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            Toggle("Sempre visível por cima", isOn: $settings.alwaysOnTop)
            Toggle("Mostrar a resposta enquanto chega", isOn: $settings.streaming)
            Button("Centralizar na tela") { PetWindowController.shared?.centerOnScreen() }
        } header: {
            Text("Aparência")
        }
    }

    private var conversation: some View {
        Section {
            HStack {
                Button("Nova conversa") { ChatStore.shared.newChat() }
                Button("Limpar balões") { ChatStore.shared.clearChat() }
                Spacer()
                Text("\(ChatStore.shared.messages.count) balões")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Conversa")
        }
    }

    // MARK: - actions

    private func saveKey() {
        settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        note = "Chave salva. 🦕"
        Task { await loadModels() }
    }

    private func testKey() async {
        busy = true
        defer { busy = false }
        do {
            let available = try await OpenCodeGo.availableModels(
                apiKey: settings.apiKey, sessionID: OpenCodeGo.newSessionID())
            note = "Chave válida — \(available.count) modelos disponíveis."
        } catch {
            note = "Falhou: \(error.localizedDescription)"
        }
    }

    private func loadModels() async {
        busy = true
        defer { busy = false }
        do {
            let available = try await OpenCodeGo.availableModels(
                apiKey: settings.apiKey, sessionID: OpenCodeGo.newSessionID())
            models = available
            if !available.isEmpty, !available.contains(settings.model) {
                settings.model = available[0]
            }
        } catch {
            note = "Não consegui listar os modelos: \(error.localizedDescription)"
        }
    }

    private func pretty(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
