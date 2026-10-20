import Foundation
import LlamaSwift

/// Одна реплика диалога. Ролей три, и для маленькой модели они значат больше,
/// чем текст внутри: «хочу есть» от user модель читает как голод человека.
public struct ChatMessage: Sendable, Hashable {
    public enum Role: String, Sendable { case system, user, assistant }
    public let role: Role
    public let content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> ChatMessage { .init(.user, text) }
    public static func assistant(_ text: String) -> ChatMessage { .init(.assistant, text) }
}

/// Параметры генерации. Длина задаётся здесь, а не словами в промпте:
/// генерация останавливается сразу после `maxSentences`-й точки.
public struct GenerationOptions: Sendable {
    public var maxTokens = 160
    public var temperature: Float = 0.7
    public var topK: Int32 = 20
    public var topP: Float = 0.85
    public var minP: Float = 0.05
    public var repeatPenalty: Float = 1.1
    public var maxSentences: Int? = 2
    public var seed: UInt32 = 1

    public init() {}
}

public struct Generation: Sendable {
    public let text: String
    public let promptTokens: Int
    public let generatedTokens: Int
    public let prefillSeconds: Double
    public let decodeSeconds: Double

    public var tokensPerSecond: Double {
        decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0
    }
}

public enum LlamaChatError: Error, CustomStringConvertible {
    case modelLoad(String)
    case context
    case tokenize
    case promptTooLong(Int)
    case decode(Int32)

    public var description: String {
        switch self {
        case .modelLoad(let path): "Не удалось загрузить модель: \(path)"
        case .context: "Не удалось создать контекст llama.cpp"
        case .tokenize: "Не удалось токенизировать промпт"
        case .promptTooLong(let count): "Промпт не помещается в контекст: \(count) токенов"
        case .decode(let status): "llama_decode вернул \(status)"
        }
    }
}

/// Минимальный чат поверх C API llama.cpp: шаблон, сэмплеры, стоп по предложениям.
///
/// Вызовы идут строго по одному: контекст у модели один, и две генерации
/// одновременно испортили бы друг другу кэш.
public final class LlamaChat: @unchecked Sendable {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let lock = NSLock()
    private let batchSize: Int32 = 512
    /// Qwen собирается вручную: его шаблон открывает блок рассуждения, и пустой
    /// `<think></think>` выключает его так же, как в Mewmori.
    private let usesChatML: Bool

    public let contextLength: Int

    private static let backend: Void = llama_backend_init()

    public init(modelPath: String, contextLength: UInt32 = 2048) throws {
        _ = Self.backend
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = -1
        #endif
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaChatError.modelLoad(modelPath)
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = contextLength
        contextParams.n_batch = UInt32(batchSize)
        contextParams.n_ubatch = 256
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaChatError.context
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.contextLength = Int(llama_n_ctx(context))
        let template = llama_model_chat_template(model, nil).map { String(cString: $0) } ?? ""
        self.usesChatML = template.contains("<|im_start|>")
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    // MARK: - Prompt

    func prompt(for messages: [ChatMessage]) -> String {
        if usesChatML {
            let turns = messages.map { "<|im_start|>\($0.role.rawValue)\n\($0.content)<|im_end|>\n" }.joined()
            return turns + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        }
        let template = llama_model_chat_template(model, nil)
        let roles = messages.map { strdup($0.role.rawValue)! }
        let contents = messages.map { strdup($0.content)! }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        var chat = zip(roles, contents).map { llama_chat_message(role: $0, content: $1) }
        var buffer = [CChar](repeating: 0, count: 8192)
        var length = llama_chat_apply_template(template, &chat, chat.count, true, &buffer, Int32(buffer.count))
        if length > Int32(buffer.count) {
            buffer = [CChar](repeating: 0, count: Int(length) + 1)
            length = llama_chat_apply_template(template, &chat, chat.count, true, &buffer, Int32(buffer.count))
        }
        let bytes = buffer.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        let capacity = text.utf8.count + 8
        var tokens = [llama_token](repeating: 0, count: capacity)
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(capacity), true, true)
        guard count > 0 else { throw LlamaChatError.tokenize }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return [] }
        return buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    }

    // MARK: - Generation

    public func generate(_ messages: [ChatMessage], options: GenerationOptions = .init()) throws -> Generation {
        lock.lock()
        defer { lock.unlock() }

        // Каждый вызов одноходовый: история приходит в сообщениях, кэш не переиспользуется.
        llama_memory_clear(llama_get_memory(context), true)

        let tokens = try tokenize(prompt(for: messages))
        guard tokens.count + options.maxTokens < contextLength else {
            throw LlamaChatError.promptTooLong(tokens.count)
        }

        var batch = llama_batch_init(batchSize, 0, 1)
        defer { llama_batch_free(batch) }

        let prefillStart = Date()
        var position: Int32 = 0
        var index = 0
        while index < tokens.count {
            let chunk = tokens[index..<min(index + Int(batchSize), tokens.count)]
            batch.n_tokens = 0
            for (offset, token) in chunk.enumerated() {
                add(token, at: position + Int32(offset), logits: index + offset == tokens.count - 1, to: &batch)
            }
            let status = llama_decode(context, batch)
            guard status == 0 else { throw LlamaChatError.decode(status) }
            position += Int32(chunk.count)
            index += chunk.count
        }
        let prefillSeconds = Date().timeIntervalSince(prefillStart)

        let sampler = makeSampler(options)
        defer { llama_sampler_free(sampler) }

        var bytes: [UInt8] = []
        var generated = 0
        let decodeStart = Date()
        while generated < options.maxTokens {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token)
            generated += 1

            let text = String(decoding: bytes, as: UTF8.self)
            if text.hasSuffix("<|im_end|>") { break }
            if let limit = options.maxSentences, Sentences.completedCount(in: text) >= limit { break }

            batch.n_tokens = 0
            add(token, at: position, logits: true, to: &batch)
            position += 1
            let status = llama_decode(context, batch)
            guard status == 0 else { throw LlamaChatError.decode(status) }
        }

        let text = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Generation(
            text: text,
            promptTokens: tokens.count,
            generatedTokens: generated,
            prefillSeconds: prefillSeconds,
            decodeSeconds: Date().timeIntervalSince(decodeStart)
        )
    }

    private func add(_ token: llama_token, at position: Int32, logits: Bool, to batch: inout llama_batch) {
        let slot = Int(batch.n_tokens)
        batch.token[slot] = token
        batch.pos[slot] = position
        batch.n_seq_id[slot] = 1
        batch.seq_id[slot]![0] = 0
        batch.logits[slot] = logits ? 1 : 0
        batch.n_tokens += 1
    }

    /// Тот же порядок, что в Mewmori: штраф за повтор, top-k, top-p, min-p, температура.
    private func makeSampler(_ options: GenerationOptions) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, options.repeatPenalty, 0, 0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(options.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(options.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(options.minP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(options.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(options.seed))
        return chain
    }
}

/// Счётчик законченных предложений. Многоточие - одна граница, точка между
/// цифрами - не граница.
public enum Sentences {
    public static func completedCount(in text: String) -> Int {
        let characters = Array(text)
        let terminators: Set<Character> = [".", "!", "?", "…"]
        var count = 0
        var index = 0
        while index < characters.count {
            guard terminators.contains(characters[index]) else {
                index += 1
                continue
            }
            let isDecimal = characters[index] == "."
                && index > 0 && characters[index - 1].isNumber
                && index + 1 < characters.count && characters[index + 1].isNumber
            var end = index
            while end + 1 < characters.count, terminators.contains(characters[end + 1]) { end += 1 }
            if !isDecimal { count += 1 }
            index = end + 1
        }
        return count
    }
}
