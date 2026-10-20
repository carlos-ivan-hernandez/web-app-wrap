import Foundation
import WebAppWrapKit

/// Which WebAppWrap this is: the commit scripts/build.sh built it from. An app in the list is
/// rebuilt when this changes. `swift run` builds have no Info.plist, so no version.
enum GeneratorVersion {
    static let commit: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: WrapperInfoKeys.generatorCommit) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }()

    /// "71471f3", "71471f3-dirty" or "development build".
    static func describe(_ commit: String?) -> String {
        guard let commit else { return "development build" }
        let dirty = commit.hasSuffix("-dirty")
        let sha = dirty ? String(commit.dropLast("-dirty".count)) : commit
        return String(sha.prefix(7)) + (dirty ? "-dirty" : "")
    }

    static var display: String { describe(commit) }
}
