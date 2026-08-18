import Foundation

/// Where the backend lives. Values come from Info.plist so the simulator and CI
/// can override them with environment variables without a rebuild.
///
/// Only the publishable key ever ships in the binary. It is a public key by
/// design: every row it can reach is gated by row-level security, and the
/// service-role key (which bypasses RLS entirely) lives in
/// `~/.aging_credentials` and is never referenced from app code.
enum SupabaseConfig {
    /// In DEBUG the environment wins over the Info.plist, so a UI test can aim
    /// the app at an unroutable host and hand it, from the app's own point of
    /// view, exactly what airplane mode does: every request failing at the
    /// transport layer. That is what `OfflineLaunchUITests` needs, and it is not
    /// otherwise reproducible on a headless simulator. Release builds read only
    /// the Info.plist, so no shipped binary can be redirected this way.
    static let url: URL = {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? ""
        #else
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        #endif
        return URL(string: raw) ?? URL(string: "https://placeholder.supabase.co")!
    }()

    static let anonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
    }()

    static var isConfigured: Bool {
        !anonKey.isEmpty && url.host?.contains("placeholder") == false
    }
}
