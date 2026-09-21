import Foundation

/// The one way a file path is written down when it has to be compared with another.
///
/// Test file paths reach the cache from two directions — hashed by `TestFilesHasher`, and named as
/// a mutant's killer by `KillerTestFileResolver` — and `CacheStore.invalidate` only works when both
/// arrive in the same form. They used to disagree, so no killed verdict was ever invalidated by an
/// edit to the test that killed it (issue #67).
///
/// Symlinks are resolved on both sides before comparing, because the sandbox links source files
/// back to the project and either form can turn up.
enum ProjectRelativePath {

    /// `path` written relative to `projectPath`, or unchanged when it lies outside the project.
    static func make(for path: String, in projectPath: String) -> String {
        let root = URL(fileURLWithPath: projectPath).resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path

        guard resolved.hasPrefix(root + "/") else { return path }

        return String(resolved.dropFirst(root.count + 1))
    }
}
