import SwiftUI
import Network
import UIKit
import Combine

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { ToolsView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            NavigationStack { LocalServicesView() }
                .tabItem { Label("Scan", systemImage: "dot.radiowaves.left.and.right") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Explorer").font(.largeTitle.bold())
                    Label(appState.isConnected ? "Connected · \(appState.connectionType)" : "Offline", systemImage: appState.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appState.isConnected ? .green : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))

                Text("Quick Access").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach([ToolKind.speed, .ping, .dns, .connection], id: \.self) { tool in
                        NavigationLink(destination: ToolDetailView(tool: tool)) {
                            ToolTile(tool: tool)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Recent Results").font(.title2.bold())
                if let entry = appState.history.first {
                    HistoryCard(entry: entry)
                } else {
                    ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Completed tests will appear here."))
                }
            }
            .padding()
        }
        .navigationTitle("NetPulse")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ToolTile: View {
    let tool: ToolKind
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: tool.symbol).font(.title2).foregroundStyle(.cyan)
            Text(tool.rawValue).font(.headline)
            Text(tool.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(15)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ToolsView: View {
    var body: some View {
        List {
            Section("Network Tools") {
                ForEach(ToolKind.allCases) { tool in
                    NavigationLink(destination: ToolDetailView(tool: tool)) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.rawValue)
                                Text(tool.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: tool.symbol).foregroundStyle(.cyan)
                        }
                    }
                }
            }
        }
        .navigationTitle("Tools")
    }
}

struct ToolDetailView: View {
    let tool: ToolKind
    @EnvironmentObject private var appState: AppState
    @State private var target = "example.com"
    @State private var output = "Ready"
    @State private var isRunning = false
    @State private var errorMessage: String?

    private var usesTarget: Bool {
        [.ping, .dns, .http, .connection].contains(tool)
    }

    var body: some View {
        Form {
            Section {
                Label(tool.subtitle, systemImage: tool.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if usesTarget {
                Section("Target") {
                    TextField(tool == .http ? "https://example.com" : "Hostname or IP", text: $target)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().padding(.trailing, 4) }
                        Text(isRunning ? "Testing…" : actionTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isRunning || tool == .udpQuality || tool == .localServices)
            }
            Section("Result") {
                Text(output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if tool == .udpQuality {
                Section("Reconstruction note") {
                    Text("The binary indicates UDP/STUN quality tests (latency, jitter, packet loss), but its probe encoding and server-selection algorithm cannot be faithfully recovered from strings and symbols alone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if tool == .localServices {
                Section { NavigationLink("Open Bonjour scanner", destination: LocalServicesView()) }
            }
        }
        .navigationTitle(tool.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Test failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unknown error") }
        .onAppear { output = tool.subtitle }
    }

    private var actionTitle: String {
        tool == .speed ? "Start Test" : tool == .publicIP ? "Look Up IP" : "Start Test"
    }

    @MainActor
    private func runTest() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let result: String
            switch tool {
            case .speed: result = try await NetworkTests.runSpeedTest()
            case .ping: result = try await NetworkTests.reachability(target)
            case .dns: result = try await NetworkTests.resolveDNS(target)
            case .http: result = try await NetworkTests.httpRequest(target)
            case .connection: result = try await NetworkTests.quickDiagnosis(target)
            case .publicIP: result = try await NetworkTests.publicIP()
            case .localServices: result = "Use the Scan tab to browse Bonjour services."
            case .udpQuality: result = "Not implemented in this reconstruction."
            }
            output = result
            appState.addHistory(tool: tool, summary: result.components(separatedBy: "\n").first ?? result)
        } catch {
            errorMessage = error.localizedDescription
            output = "Failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class BonjourScanner: ObservableObject {
    @Published private(set) var services: [String] = []
    @Published private(set) var status = "Not started"
    private var browsers: [NWBrowser] = []
    private let serviceTypes = ["_http._tcp", "_https._tcp", "_ssh._tcp", "_smb._tcp", "_ipp._tcp"]

    func start() {
        stop()
        services.removeAll()
        status = "Searching local Bonjour services…"
        browsers = serviceTypes.map { type in
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    DispatchQueue.main.async { self?.status = "Browser error: \(error.localizedDescription)" }
                }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let found = results.compactMap { result -> String? in
                    guard case let .service(name, serviceType, domain, _) = result.endpoint else { return nil }
                    return "\(name)  ·  \(serviceType)  ·  \(domain)"
                }
                DispatchQueue.main.async {
                    self?.services = Array(Set((self?.services ?? []) + found)).sorted()
                    self?.status = self?.services.isEmpty == false ? "Discovery active" : "No services found yet"
                }
            }
            browser.start(queue: .main)
            return browser
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
    }

    deinit { browsers.forEach { $0.cancel() } }
}

struct LocalServicesView: View {
    @StateObject private var scanner = BonjourScanner()

    var body: some View {
        List {
            Section {
                Text("This sample browses selected Bonjour service types. It does not sweep IP ranges, inspect ARP tables, or guarantee that every local device is discoverable.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Start Local Discovery") { scanner.start() }
                Button("Stop") { scanner.stop() }
                Text(scanner.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Discovered Services") {
                if scanner.services.isEmpty {
                    Text("No Bonjour services found").foregroundStyle(.secondary)
                } else {
                    ForEach(scanner.services, id: \.self) { Text($0).font(.callout) }
                }
            }
        }
        .navigationTitle("Local Services")
        .onDisappear { scanner.stop() }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock.arrow.circlepath", description: Text("Your recent network-test results are stored on this device for up to 14 days."))
            } else {
                List {
                    ForEach(appState.history) { entry in HistoryCard(entry: entry) }
                    Button("Clear History", role: .destructive) { appState.clearHistory() }
                }
            }
        }
        .navigationTitle("Task History")
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.tool).font(.headline)
                Spacer()
                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            Section("About") {
                LabeledContent("App", value: "NetPulse Reconstruction")
                LabeledContent("Platform", value: "iOS 17+")
                LabeledContent("History retention", value: "14 days")
            }
            Section("Scope") {
                Text("This is a clean-room approximation based on an IPA’s metadata, Swift symbols, and localized strings. It is not the original source code and omits features whose algorithms or entitlements could not be verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
