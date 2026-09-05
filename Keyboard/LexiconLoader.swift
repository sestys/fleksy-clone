import Foundation
import FleksyCore

/// Loads bundled frequency lists lazily on a background queue.
final class LexiconLoader: LexiconProvider {
    private var cache: [Language: Lexicon] = [:]
    private var loading: Set<Language> = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "fleksy.lexicon", qos: .userInitiated)
    var onLoaded: ((Language) -> Void)?

    func lexicon(for language: Language) -> Lexicon? {
        lock.lock(); defer { lock.unlock() }
        if let l = cache[language] { return l }
        if !loading.contains(language) {
            loading.insert(language)
            queue.async { [weak self] in self?.load(language) }
        }
        return nil
    }

    func preload(_ languages: [Language]) {
        for l in languages { _ = lexicon(for: l) }
    }

    private func load(_ language: Language) {
        let bundle = Bundle(for: LexiconLoader.self)
        let url = bundle.url(forResource: language.lexiconResource, withExtension: "txt", subdirectory: "Dictionaries")
            ?? bundle.url(forResource: language.lexiconResource, withExtension: "txt")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            lock.lock(); loading.remove(language); lock.unlock()
            return
        }
        let lex = Lexicon(language: language, text: text)
        lock.lock()
        cache[language] = lex
        loading.remove(language)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onLoaded?(language) }
    }
}
