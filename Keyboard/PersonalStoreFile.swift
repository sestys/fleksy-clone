import Foundation
import FleksyCore

/// Keeps the personal model in a JSON file in the extension's own container.
///
/// Not UserDefaults: the counts change on every committed word and are far larger than
/// a preference. Not an App Group either, for the same reason the rest of the settings
/// aren't — that would need a paid developer account. The cost is that the containing
/// app cannot read what the keyboard has learned.
final class PersonalStoreFile: PersonalStore {
    private let url: URL?

    init(filename: String = "personal.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let directory else { url = nil; return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
    }

    func load() -> [Language: PersonalCounts] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        // A corrupt or outdated file is not worth failing over: the model rebuilds itself
        // from ordinary typing within a few sentences.
        return (try? JSONDecoder().decode([Language: PersonalCounts].self, from: data)) ?? [:]
    }

    func save(_ counts: [Language: PersonalCounts]) {
        guard let url, let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
