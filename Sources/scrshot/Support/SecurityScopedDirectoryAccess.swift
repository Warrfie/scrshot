import Foundation

final class SecurityScopedDirectoryAccess {
    let url: URL

    private var isAccessing: Bool

    init(url: URL) {
        self.url = url
        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        stop()
    }

    func stop() {
        guard isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }
}
