import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView()
        #if DEBUG
        banner.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        #else
        banner.adUnitID = "YOUR_BANNER_AD_UNIT_ID"
        #endif
        banner.adSize = AdSizeBanner
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
