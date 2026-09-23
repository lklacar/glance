import Foundation

/// Store URL strings, not bookmarks whose resolution could contact a remote volume.
public enum RecentImages {
    private static let key = "rs.qubit.glance.recentImages"
    public static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(URL.init(string:)).filter(\.isFileURL)
    }
    public static func note(_ url: URL) {
        let recent = [url] + urls.filter { $0 != url }
        UserDefaults.standard.set(Array(recent.prefix(20)).map(\.absoluteString), forKey: key)
    }
    public static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
