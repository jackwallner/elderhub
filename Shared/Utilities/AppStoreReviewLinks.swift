import Foundation

/// App Store deep links for Elderhub.
enum AppStoreReviewLinks {
    static let appStoreID = "6796916172"

    /// The write-review page in the reader's own storefront. Apple routes
    /// correctly without the country segment too, so an unknown storefront is
    /// not a reason to fail.
    static var writeReviewURL: URL {
        URL(string: writeReviewURLString)!
    }

    private static var writeReviewURLString: String {
        if let country = storefrontCountryCode {
            return "https://apps.apple.com/\(country)/app/id\(appStoreID)?action=write-review"
        }
        return "https://apps.apple.com/app/id\(appStoreID)?action=write-review"
    }

    /// The device region, which is the right segment often enough and is never
    /// wrong in a way that matters: Apple resolves an id-only link to the
    /// reader's own storefront regardless. The fleet's alpha-3 storefront
    /// lookup is not worth carrying here for that, and its `SKPaymentQueue`
    /// accessor is deprecated.
    private static var storefrontCountryCode: String? {
        guard let region = Locale.current.region?.identifier.lowercased(),
              region.count == 2 else { return nil }
        return region
    }
}
