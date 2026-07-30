import Foundation
import Supabase

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabasePublishableKey: String

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let rawURL = (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawKey = (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return AppConfiguration(
            supabaseURL: URL(string: rawURL),
            supabasePublishableKey: rawKey
        )
    }

    var validationMessage: String? {
        guard let supabaseURL,
              supabaseURL.scheme == "https",
              supabaseURL.host?.hasSuffix(".supabase.co") == true else {
            return "Add a valid SUPABASE_URL to Config/Local.xcconfig."
        }
        guard supabasePublishableKey.hasPrefix("sb_publishable_") || supabasePublishableKey.count > 40 else {
            return "Add the Supabase publishable key to Config/Local.xcconfig."
        }
        return nil
    }

    func makeSupabaseClient() -> SupabaseClient? {
        guard validationMessage == nil, let supabaseURL else { return nil }
        return SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabasePublishableKey
        )
    }
}
