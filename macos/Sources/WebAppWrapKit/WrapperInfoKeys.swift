/// Info.plist keys the generator writes and the runtime reads.
public enum WrapperInfoKeys {
    public static let baseURL = "WebAppWrapBaseURL"
    /// "#RRGGBB" background for the tab bar.
    public static let titleBarColor = "WebAppWrapTitleBarColor"
    /// The commit WebAppWrap was built from. scripts/build.sh writes it into WebAppWrap's own
    /// Info.plist, and WebAppWrap copies it into every app it creates.
    public static let generatorCommit = "WebAppWrapCommit"
    /// The app's ID in WebAppWrap's list (AppRecord.id), used to look up which extensions are
    /// on for it. Apps made from the command line don't have one.
    public static let appID = "WebAppWrapAppID"
}
