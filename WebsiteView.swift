//
//  WebsiteView.swift
//  Radio-WeinWelle-Player
//

import SwiftUI
import WebKit

struct WebsiteView: View {
    let url: URL

    var body: some View {
        WebView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)
    }
}

/// Plattformübergreifender WKWebView-Wrapper.
private struct WebView {
    let url: URL
}

#if canImport(UIKit)
import UIKit
extension WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url { webView.load(URLRequest(url: url)) }
    }
}
#elseif canImport(AppKit)
import AppKit
extension WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url { webView.load(URLRequest(url: url)) }
    }
}
#endif

#Preview {
    WebsiteView(url: URL(string: "https://www.radio-wein-welle.de")!)
}
