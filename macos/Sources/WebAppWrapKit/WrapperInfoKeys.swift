/// Info.plist keys the generator writes and the runtime reads.
public enum WrapperInfoKeys {
    public static let baseURL = "WebAppWrapBaseURL"
    /// "#RRGGBB" background for the tab bar.
    public static let titleBarColor = "WebAppWrapTitleBarColor"
    /// The commit WebAppWrap was built from. scripts/build.sh writes it into WebAppWrap's own
    /// Info.plist, and WebAppWrap copies it into every app it creates.
    public static let generatorCommit = "WebAppWrapCommit"
}
