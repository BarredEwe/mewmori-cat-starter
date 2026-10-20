#if canImport(CatPocketCore)
import CatPocketCore
#endif
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var history: [ChatMessage] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var lastSpeed: Double?

    private let persona = CatPersona()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, message in
                                Bubble(message: message).id(index)
                            }
                            if isThinking {
                                Text("…").font(.title2).foregroundStyle(.secondary).padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: history.count) { _, count in
                        withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
                HStack {
                    TextField("Скажите что-нибудь коту", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("CatPocket.Input")
                        .onSubmit(send)
                    Button("Отправить", action: send)
                        .disabled(draft.isEmpty || isThinking)
                        .accessibilityIdentifier("CatPocket.Send")
                }
                .padding()
            }
            .navigationTitle(persona.catName)
            .toolbar {
                if let lastSpeed {
                    Text(String(format: "%.0f ток/с", lastSpeed)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, let chat = store.chat else { return }
        draft = ""
        history.append(.user(text))
        isThinking = true
        // Окно истории короткое: кот помнит последние шесть реплик, не больше.
        let messages = persona.messages(history: Array(history.suffix(6)))
        Task.detached(priority: .userInitiated) {
            var options = GenerationOptions()
            options.seed = UInt32.random(in: 1..<UInt32.max)
            let reply = (try? chat.generate(messages, options: options))
            await MainActor.run {
                history.append(.assistant(reply?.text.isEmpty == false ? reply!.text : "Мяу."))
                lastSpeed = reply?.tokensPerSecond
                isThinking = false
            }
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        let isCat = message.role == .assistant
        HStack {
            if !isCat { Spacer(minLength: 40) }
            Text(message.content)
                .padding(10)
                .background(isCat ? Color(.secondarySystemBackground) : Color.accentColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if isCat { Spacer(minLength: 40) }
        }
    }
}
