import Foundation
import LlamaSwift

enum LocalCatModel {
    static func generate(modelPath: String, prompt: String, maxTokens: Int = 96) -> String {
        llama_backend_init()
        defer { llama_backend_free() }

        let modelParams = llama_model_default_params()
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            fatalError("Не удалось загрузить GGUF-модель: \(modelPath)")
        }
        defer { llama_model_free(model) }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048
        contextParams.n_batch = 512
        guard let context = llama_init_from_model(model, contextParams) else {
            fatalError("Не удалось создать контекст llama.cpp")
        }
        defer { llama_free(context) }

        let vocab = llama_model_get_vocab(model)
        let utf8Count = prompt.utf8.count
        var tokens = [llama_token](repeating: 0, count: utf8Count + 1)
        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(utf8Count),
            &tokens,
            Int32(tokens.count),
            true,
            true
        )
        guard tokenCount > 0 else {
            fatalError("Не удалось токенизировать prompt")
        }

        let promptTokens = Array(tokens.prefix(Int(tokenCount)))
        var batch = llama_batch_init(Int32(contextParams.n_batch), 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = Int32(promptTokens.count)

        for index in promptTokens.indices {
            batch.token[index] = promptTokens[index]
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.logits[index] = 0
            if let seqIDs = batch.seq_id, let seqID = seqIDs[index] {
                seqID[0] = 0
            }
        }
        batch.logits[promptTokens.count - 1] = 1

        guard llama_decode(context, batch) == 0 else {
            fatalError("llama_decode для prompt завершился ошибкой")
        }

        var generatedText = ""
        var currentPosition = batch.n_tokens

        for _ in 0..<maxTokens {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                fatalError("Не удалось получить logits")
            }

            let vocabularySize = llama_vocab_n_tokens(vocab)
            var maxLogit = logits[0]
            var nextToken: llama_token = 0
            for index in 1..<Int(vocabularySize) where logits[index] > maxLogit {
                maxLogit = logits[index]
                nextToken = llama_token(index)
            }

            if nextToken == llama_vocab_eos(vocab) {
                break
            }

            var buffer = [CChar](repeating: 0, count: 128)
            let length = llama_token_to_piece(
                vocab,
                nextToken,
                &buffer,
                Int32(buffer.count),
                0,
                false
            )
            if length > 0 {
                let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
                generatedText += String(decoding: bytes, as: UTF8.self)
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = currentPosition
            batch.n_seq_id[0] = 1
            batch.logits[0] = 1
            currentPosition += 1
            if let seqIDs = batch.seq_id, let seqID = seqIDs[0] {
                seqID[0] = 0
            }

            guard llama_decode(context, batch) == 0 else {
                fatalError("llama_decode для токена завершился ошибкой")
            }
        }

        return generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
