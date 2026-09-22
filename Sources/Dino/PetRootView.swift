import SwiftUI

struct PetRootView: View {
    @State private var store = ChatStore.shared
    @State private var settings = AppSettings.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        widget
            .padding(Metrics.shadowPadding)
            // The panel is non-activating so that clicking the dino does not
            // yank focus out of whatever you were doing. The flip side is that
            // the app is not "active", and system input - dictation above all -
            // only targets the active app. So activate only when the text field
            // is actually focused, which is exactly when you want to type.
            .onChange(of: inputFocused) { _, focused in
                if focused { NSApp.activate(ignoringOtherApps: true) }
            }
    }

    private var widget: some View {
        VStack(spacing: 8) {
            header
            transcript
            inputRow
        }
        .padding(14)
        // Fills the panel so the widget can be resized instead of sitting in a
        // fixed box.
        .frame(minWidth: Metrics.minContent.width,
               maxWidth: .infinity,
               minHeight: Metrics.minContent.height,
               maxHeight: .infinity)
        .widgetCard()
        .contextMenu {
            Button("Nova conversa") { store.newChat() }
            Button("Preferências…") { AppCommands.openSettings() }
            Divider()
            Button("Sair do Dino") { NSApp.terminate(nil) }
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.needsKey ? Palette.blush
                      : store.isOffline ? Palette.offline
                      : Palette.skin)
                .frame(width: 8, height: 8)
            Text("Dino")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.onGlass)
            Text(status)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(store.isOffline && !store.needsKey
                                 ? Palette.offline : Palette.onGlassDim)
            Spacer(minLength: 4)
            iconButton("arrow.counterclockwise", help: "Nova conversa") { store.newChat() }
            iconButton(settings.alwaysOnTop ? "pin.fill" : "pin",
                       help: settings.alwaysOnTop
                           ? "Fixado por cima — clique para soltar"
                           : "Fixar por cima das outras janelas",
                       active: settings.alwaysOnTop) {
                settings.alwaysOnTop.toggle()
            }
            iconButton("gearshape.fill", help: "Preferências") { AppCommands.openSettings() }
        }
        .padding(.horizontal, 4)
    }

    private var status: String {
        if store.needsKey { return "esperando a chave" }
        if store.isOffline { return "offline" }
        return store.isBusy ? "pensando…" : "online"
    }

    private func iconButton(_ name: String, help: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { iconLabel(name, active: active) }
            .buttonStyle(.plain)
            .help(help)
    }

    private func iconLabel(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Palette.ink : Palette.onGlass)
            .frame(width: 24, height: 24)
            .background(Circle().fill(
                active ? AnyShapeStyle(Palette.skin) : AnyShapeStyle(Color.white.opacity(0.18))))
    }

    // MARK: - transcript

    private var transcript: some View {
        GeometryReader { geo in
            // Height of the soft edge, used both for the mask and for the
            // padding that keeps a message from resting inside the fade.
            let fade = max(14, geo.size.height * 0.07)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.messages) { message in
                            BalloonRow(message: message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.top, 6 + fade)
                    .padding(.bottom, 6 + fade)
                    // Keeps a short conversation resting on the dino instead of
                    // floating at the top, the way a chat transcript behaves.
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .animation(.spring(response: 0.34, dampingFraction: 0.82),
                               value: store.messages.count)
                }
                .defaultScrollAnchor(.bottom)
                .scrollIndicators(.never)
                // Dissolve the transcript into the glass at the edges instead
                // of guillotining balloons where the dino's row begins.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.07),
                            .init(color: .black, location: 0.93),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .onChange(of: store.messages.count) { _, _ in
                    scrollToEnd(proxy, animated: true)
                }
                .onChange(of: store.messages.last?.text) { _, _ in
                    // No animation while tokens stream in, or it fights layout.
                    scrollToEnd(proxy, animated: false)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = store.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - input

    private var inputRow: some View {
        // Side by side while there is room for a usable text field. Once the
        // widget is narrow enough that the field would collapse (the
        // placeholder ends up one letter per line), the dino moves up and the
        // input gets the full width to itself.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                // The dino stands on the same side as its own balloons.
                dino
                inputControl
            }
            VStack(spacing: 6) {
                dino
                inputControl
            }
        }
        // Leave the bottom-right corner to the resize grip so it cannot sit on
        // top of the send button.
        .padding(.trailing, Metrics.resizeGripClearance)
    }

    private var dino: some View {
        DinoSprite(scale: settings.spriteScale, isThinking: store.isBusy)
    }

    @ViewBuilder
    private var inputControl: some View {
        if store.needsKey { keyField } else { promptField }
    }

    /// First run (or a rejected key): the input row asks for the key and saves
    /// it exactly where the Settings window would.
    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.skinDeep)
                SecureField("Cola sua API key do OpenCode Go", text: $store.keyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .focused($inputFocused)
                    .onSubmit { store.submitKey() }
                    .disabled(store.isValidatingKey)
                if store.isValidatingKey {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Salvar") { store.submitKey() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.skinDeep)
                        .disabled(store.keyDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(capsule)
            .modifier(FocusOnTap(focus: $inputFocused))

            Text("Fica salvo em \(secretsPath) (só você lê)")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(Palette.onGlassFaint)
                .padding(.leading, 4)
        }
        .frame(minWidth: Metrics.minInputWidth)
    }

    private var secretsPath: String {
        Secrets.location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var promptField: some View {
        HStack(spacing: 7) {
            TextField("Fala comigo~", text: $store.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                // The field must not size itself from its content, or a long
                // message would push the row wider and make ViewThatFits drop
                // the dino above the input. Pinning the ideal width keeps the
                // row's fit decision independent of what is typed.
                .frame(minWidth: 0, idealWidth: Metrics.minInputWidth,
                       maxWidth: .infinity, alignment: .leading)
                .focused($inputFocused)
                .onSubmit { store.send() }
            Button {
                if store.isBusy { store.stopReply() } else { store.send() }
            } label: {
                Image(systemName: store.isBusy ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(
                        store.isBusy
                            ? AnyShapeStyle(Palette.skinDeep)
                            : store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AnyShapeStyle(Palette.skin.opacity(0.45))
                                : AnyShapeStyle(Palette.skinDeep)))
            }
            .buttonStyle(.plain)
            .help(store.isBusy ? "Parar" : "Enviar")
            .disabled(!store.isBusy && store.draft.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(minWidth: Metrics.minInputWidth)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(capsule)
        .modifier(FocusOnTap(focus: $inputFocused))
    }

    private var capsule: some View {
        Capsule(style: .continuous)
            .fill(Palette.cream)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Palette.skinDeep.opacity(0.22), lineWidth: 1)
            }
    }
}

/// Makes the whole input capsule a click target for its field. On its own the
/// field only takes clicks on its one line of text; the padding around it was
/// dead. The buttons inside keep their own taps, which win over this one.
private struct FocusOnTap: ViewModifier {
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { focus.wrappedValue = true }
    }
}
