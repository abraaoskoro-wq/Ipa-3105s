import SwiftUI
import UIKit
import AVFoundation
import Security
import CryptoKit

struct ContentView: View {
    @StateObject private var camera = RearCameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCamera = true
    @State private var showLicense = false
    @State private var checkingLicense = false
    @State private var licenseMessage = ""

    var body: some View {
        Group {
            if showCamera {
                cameraScreen
            } else {
                AppHomeView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            guard phase == .active, !showCamera else { return }
            revalidateActiveLicense()
        }
    }

    private var cameraScreen: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 1170
            let topHeight = 339 * scale
            let bottomHeight = 634 * scale
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session).ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack {
                        Color.black.opacity(0.72)
                        bundleImage(named: "CameraTop").resizable()
                    }
                    .frame(width: proxy.size.width, height: topHeight)

                    Spacer(minLength: 0)

                    ZStack {
                        Color.black.opacity(0.72)
                        bundleImage(named: "CameraBottom").resizable()

                        Button(action: handleShutterTap) {
                            Color.white.opacity(0.001)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tirar foto e entrar no aplicativo")
                        .contentShape(Rectangle())
                        .frame(width: 240 * scale, height: 220 * scale)
                        .position(x: proxy.size.width / 2, y: 205 * scale)
                        .zIndex(20)
                    }
                    .frame(width: proxy.size.width, height: bottomHeight)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: 18 * scale) {
                        Text("0,5").foregroundStyle(.white)
                        Text("1x")
                            .foregroundStyle(.yellow)
                            .frame(width: 92 * scale, height: 92 * scale)
                            .background(.white.opacity(0.18), in: Circle())
                        Text("3").foregroundStyle(.white)
                    }
                    .font(.system(size: 42 * scale, weight: .semibold))
                    .padding(.bottom, 18 * scale)
                    .frame(height: 120 * scale)
                    Color.clear.frame(height: bottomHeight)
                }
                .allowsHitTesting(false)

                if showLicense {
                    LicenseGateView(
                        isLoading: checkingLicense,
                        message: $licenseMessage,
                        onCancel: { showLicense = false },
                        onActivate: activateLicense
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func handleShutterTap() {
        guard !checkingLicense else { return }
        checkingLicense = true
        Task {
            do {
                let valid = try await LicenseService.shared.verify()
                await MainActor.run {
                    checkingLicense = false
                    if valid {
                        camera.stop()
                        showCamera = false
                    } else {
                        licenseMessage = "Nenhuma key ativa neste aparelho."
                        showLicense = true
                    }
                }
            } catch {
                await MainActor.run {
                    checkingLicense = false
                    licenseMessage = error.localizedDescription
                    showLicense = true
                }
            }
        }
    }

    private func activateLicense(key: String) {
        checkingLicense = true
        Task {
            do {
                _ = try await LicenseService.shared.activate(key: key)
                await MainActor.run {
                    checkingLicense = false
                    showLicense = false
                    camera.stop()
                    showCamera = false
                }
            } catch {
                await MainActor.run {
                    checkingLicense = false
                    licenseMessage = error.localizedDescription
                }
            }
        }
    }

    private func revalidateActiveLicense() {
        guard !checkingLicense else { return }
        checkingLicense = true
        Task {
            do {
                let valid = try await LicenseService.shared.verify()
                await MainActor.run {
                    checkingLicense = false
                    if !valid {
                        showCamera = true
                        licenseMessage = "A licença foi cancelada ou banida."
                        showLicense = true
                    }
                }
            } catch {
                await MainActor.run {
                    checkingLicense = false
                    showCamera = true
                    licenseMessage = error.localizedDescription
                    showLicense = true
                }
            }
        }
    }

    private func bundleImage(named name: String) -> Image {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let image = UIImage(contentsOfFile: path) else {
            return Image(systemName: "rectangle.fill")
        }
        return Image(uiImage: image)
    }
}

private struct LicenseGateView: View {
    let isLoading: Bool
    @Binding var message: String
    let onCancel: () -> Void
    let onActivate: (String) -> Void
    @State private var key = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "key.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.yellow)
                Text("Key necessária")
                    .font(.system(size: 26, weight: .bold))
                Text("Digite uma key de 1, 7 ou 30 dias para entrar no aplicativo.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                TextField("3105-7D-...", text: $key)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2)))
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    guard key.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else {
                        message = "Digite uma key válida."
                        return
                    }
                    message = ""
                    onActivate(key.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.black) }
                        else { Text("Ativar key") }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .foregroundStyle(.black)
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 14))
                .disabled(isLoading)
                Button("Voltar para a câmera", action: onCancel)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
    }
}

private enum LicenseError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Resposta inválida do servidor."
        case .server(let message): return message
        }
    }
}

private final class LicenseService {
    static let shared = LicenseService()

    // KeyAuth public application settings. Never embed the owner secret in the IPA.
    private let baseURL = URL(string: "https://keyauth.win/api/1.3/")!
    private let applicationName = "Abraaoscostaadmhelipa's Application"
    private let ownerID = "7N65LBbHvS"
    private let applicationVersion = "1.0"
    private let session = URLSession(configuration: .ephemeral)
    private var sessionID: String?
    private var activeKey: String?
    private let keychainService = "3105.keyauth"

    func verify() async throws -> Bool {
        guard let key = activeKey ?? loadString(account: "license-key") else { return false }
        return try await authenticate(key: key)
    }

    func activate(key: String) async throws -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw LicenseError.server("Digite uma key válida.") }
        let valid = try await authenticate(key: normalized)
        if valid {
            activeKey = normalized
            saveString(normalized, account: "license-key")
        }
        return valid
    }

    private func authenticate(key: String) async throws -> Bool {
        let sessionID = try await initializeIfNeeded()
        let object = try await request([
            URLQueryItem(name: "type", value: "license"),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "hwid", value: installationID),
            URLQueryItem(name: "sessionid", value: sessionID),
            URLQueryItem(name: "name", value: applicationName),
            URLQueryItem(name: "ownerid", value: ownerID)
        ])
        guard (object["success"] as? Bool) == true else {
            activeKey = nil
            delete(account: "license-key")
            throw LicenseError.server(object["message"] as? String ?? "Key inválida, expirada ou banida.")
        }
        let check = try await request([
            URLQueryItem(name: "type", value: "check"),
            URLQueryItem(name: "sessionid", value: sessionID),
            URLQueryItem(name: "name", value: applicationName),
            URLQueryItem(name: "ownerid", value: ownerID)
        ])
        guard (check["success"] as? Bool) == true else {
            activeKey = nil
            delete(account: "license-key")
            throw LicenseError.server(check["message"] as? String ?? "A licença foi revogada ou a sessão KeyAuth expirou.")
        }
        return true
    }

    private var installationID: String {
        if let stored = loadString(account: "installation-id") { return stored }
        let generated = "device-" + UUID().uuidString
        saveString(generated, account: "installation-id")
        return generated
    }

    private func initializeIfNeeded() async throws -> String {
        if let sessionID { return sessionID }
        let object = try await request([
            URLQueryItem(name: "type", value: "init"),
            URLQueryItem(name: "ver", value: applicationVersion),
            URLQueryItem(name: "name", value: applicationName),
            URLQueryItem(name: "ownerid", value: ownerID)
        ])
        guard (object["success"] as? Bool) == true,
              let value = object["sessionid"] as? String,
              !value.isEmpty else {
            throw LicenseError.server(object["message"] as? String ?? "Não foi possível inicializar o KeyAuth.")
        }
        sessionID = value
        return value
    }

    private func request(_ queryItems: [URLQueryItem]) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard response is HTTPURLResponse,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.invalidResponse
        }
        return object
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveString(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

private final class RearCameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "3105.rear-camera")
    private var configured = false
    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in if granted { self?.configureAndStart() } }
            return
        }
        configureAndStart()
    }
    func stop() { queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } } }
    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self, !self.configured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) else { self.session.commitConfiguration(); return }
            self.session.addInput(input)
            self.configured = true
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.videoPreviewLayer.session = session; view.videoPreviewLayer.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: PreviewView, context: Context) { view.videoPreviewLayer.session = session }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

#Preview { ContentView() }
import SwiftUI
import UIKit

struct AppHomeView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .preferredColorScheme(.dark)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("3105")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs,
                onOpenInject: { tabNavigation.select(AppSection.installed.rawValue) }
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.inject"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "cube.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}
