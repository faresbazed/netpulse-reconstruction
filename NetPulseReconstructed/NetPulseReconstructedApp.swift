import SwiftUI
import Combine
import Network

@main
struct NetPulseReconstructedApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .tint(.cyan)
        }
    }
}

enum ToolKind: String, CaseIterable, Identifiable, Hashable {
    case speed = "Speed Test"
    case ping = "Ping / Reachability"
    case dns = "DNS Query"
    case http = "HTTP Test"
    case connection = "Quick Diagnosis"
    case localServices = "Local Services"
    case publicIP = "Public IP"
    case udpQuality = "UDP Quality"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .speed: return "speedometer"
        case .ping: return "dot.radiowaves.left.and.right"
        case .dns: return "globe"
        case .http: return "arrow.left.arrow.right"
        case .connection: return "stethoscope"
        case .localServices: return "laptopcomputer.and.iphone"
        case .publicIP: return "location.circle"
        case .udpQuality: return "waveform.path"
        }
    }

    var subtitle: String {
        switch self {
        case .speed: return "Measure a small download and upload sample"
        case .ping: return "Approximate reachability with an HTTPS request"
        case .dns: return "Resolve a hostname with DNS-over-HTTPS"
        case .http: return "Send a request and inspect its response time"
        case .connection: return "Run DNS and HTTPS checks for one host"
        case .localServices: return "Discover Bonjour services on this network"
        case .publicIP: return "Read the public IP seen by Cloudflare"
        case .udpQuality: return "Not reconstructed: original STUN probe details unavailable"
        }
    }
}

struct HistoryEntry: Codable, Identifiable {
    var id: UUID
    var date: Date
    var tool: String
    var summary: String

    init(tool: String, summary: String, date: Date = .now) {
        id = UUID()
        self.date = date
        self.tool = tool
        self.summary = summary
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var connectionType = "Checking"
    @Published private(set) var history: [HistoryEntry] = []

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "netpulse.reconstruction.path-monitor")
    private let historyKey = "netpulse.reconstruction.history.v1"

    init() {
        loadHistory()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type: String
            if path.usesInterfaceType(.wifi) { type = "Wi-Fi" }
            else if path.usesInterfaceType(.wiredEthernet) { type = "Ethernet" }
            else if path.usesInterfaceType(.cellular) { type = "Cellular" }
            else { type = connected ? "Other" : "Offline" }
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.connectionType = type
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit { monitor.cancel() }

    func addHistory(tool: ToolKind, summary: String) {
        history.insert(HistoryEntry(tool: tool.rawValue, summary: summary), at: 0)
        pruneAndSave()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        history = decoded
        pruneAndSave()
    }

    private func pruneAndSave() {
        let cutoff = Date.now.addingTimeInterval(-14 * 24 * 60 * 60)
        history = history.filter { $0.date >= cutoff }
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
