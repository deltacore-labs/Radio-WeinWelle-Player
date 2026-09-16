import Foundation
import Observation

@Observable
@MainActor
final class YouTubeLiveChecker {
    private(set) var isLive = false
    private(set) var lastChecked: Date?

    func checkLiveStatus() async {
        guard let url = URL(string: "https://www.youtube.com/@RadioWeinWelle/live") else { return }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        defer { lastChecked = Date() }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            isLive = html.contains("\"isLiveNow\":true")
        } catch {
            // Netz nicht erreichbar — vorherigen isLive-Status behalten
        }
    }
}
