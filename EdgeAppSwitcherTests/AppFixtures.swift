import AppKit
@testable import EdgeAppSwitcher

func rawApp(_ pid: Int32, date: TimeInterval? = 1, url: String? = nil, bundle: String? = nil, name: String? = nil, regular: Bool = true, terminated: Bool = false, selfApp: Bool = false) -> RawApp {
    RawApp(instance: AppInstance(token: InstanceToken(pid: pid, launchDate: date.map(Date.init(timeIntervalSince1970:))), bundleURL: url.map { URL(fileURLWithPath: $0) }), bundleIdentifier: bundle, name: name, icon: nil, isRegular: regular, isTerminated: terminated, isSelf: selfApp)
}
