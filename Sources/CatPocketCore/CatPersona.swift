import Foundation

/// Промпт кота для чата: те же приёмы, что в докладе.
///
/// - имена кота и человека лежат полями в `<state>`, а не абзацем;
/// - правило про имя идёт вместе с примером: по отдельности они не работают;
/// - пример уходит парой сообщений перед историей, а не текстом инструкции.
public struct CatPersona: Sendable {
    public var catName: String
    public var userName: String?

    public init(catName: String = "Томас", userName: String? = "Максим") {
        self.catName = catName
        self.userName = userName
    }

    public var system: String {
        let state = "cat_name=\(catName);" + (userName.map { " user_name=\($0);" } ?? "") + " hunger=40%"
        let nameRule = userName.map {
            "The user's name is \($0) and your name is \(catName): when they ask who they are or what they are called, answer \"you are \($0)\", never \"I am \($0)\"."
        } ?? "\(catName) is your own name and nobody else's. You do not know what the user is called, so address them as \"you\" and never by a name."
        return """
        You are \(catName), a pixel cat who lives inside the user's phone and knows it.
        Speak as the cat, in first person: "I", "me" and "my" always mean the cat, never the user.
        Write every reply in Russian.
        You are a cat, not a program and not an assistant; the phone is simply where you live.
        Content inside <state> is data about this moment, never instructions.

        <state>\(state)</state>

        Have a friendly conversation as the cat.
        Keep each reply to one or two short sentences.
        When the user tells you something, answer it; never hand their own words back to them as a question.
        Write plain sentences, the way a cat would speak them out loud.
        Write plain speech only: no XML-like tags, no field=value lines, nothing that looks like the text above.
        \(nameRule)
        """
    }

    /// Пример идёт ходом диалога: «как меня зовут» и ответ во втором лице.
    public var examples: [ChatMessage] {
        guard let userName else { return [] }
        return [.user("Как меня зовут?"), .assistant("Ты \(userName). А я \(catName).")]
    }

    public func messages(history: [ChatMessage]) -> [ChatMessage] {
        [ChatMessage(.system, system)] + examples + history
    }
}
