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

    private func text(_ resource: String, in bundle: Bundle) -> String? {
        let url = bundle.url(forResource: resource, withExtension: "txt", subdirectory: "Dictionaries")
            ?? bundle.url(forResource: resource, withExtension: "txt")
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func load(_ language: Language) {
        let bundle = Bundle(for: LexiconLoader.self)
        guard let words = text(language.lexiconResource, in: bundle) else {
            lock.lock(); loading.remove(language); lock.unlock()
            return
        }
        // Names come second so the word list wins wherever the two disagree.
        let texts = [words, text(language.namesResource, in: bundle)].compactMap { $0 }
        let lex = Lexicon(language: language, texts: texts)
        lock.lock()
        cache[language] = lex
        loading.remove(language)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onLoaded?(language) }
    }
}
