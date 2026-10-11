import AppKit

struct InstanceToken: Hashable {
    let pid: Int32
    let launchDate: Date?
}

struct AppInstance {
    let token: InstanceToken
    let bundleURL: URL?
    // Retain the original OS object. Unknown launch dates must never fall back to PID lookup.
    let runningApplication: NSRunningApplication?

    init(token: InstanceToken, bundleURL: URL?, runningApplication: NSRunningApplication? = nil) {
        self.token = token
        self.bundleURL = bundleURL
        self.runningApplication = runningApplication
    }

    @MainActor init(application: NSRunningApplication) {
        token = InstanceToken(pid: application.processIdentifier, launchDate: application.launchDate)
        bundleURL = application.bundleURL
        runningApplication = application
    }
}

enum AppID: Hashable {
    case bundleURL(URL)
    case bundleIdentifier(String)
    case instance(InstanceToken)

    var sortKey: String {
        switch self {
        case .bundleURL(let url): return "url:" + url.absoluteString
        case .bundleIdentifier(let identifier): return "bundle:" + identifier
        case .instance(let token): return "instance:\(token.pid):\(token.launchDate?.timeIntervalSince1970.description ?? "unknown")"
        }
    }
}

struct AppRecord {
    let id: AppID
    let name: String
    let icon: NSImage?
    let instances: [AppInstance]
}

struct RawApp {
    let instance: AppInstance
    let bundleIdentifier: String?
    let name: String?
    let icon: NSImage?
    let isRegular: Bool
    let isTerminated: Bool
    let isSelf: Bool
}
