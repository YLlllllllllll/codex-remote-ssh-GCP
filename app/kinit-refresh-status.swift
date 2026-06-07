import AppKit
import Foundation

final class StatusApp: NSObject, NSApplicationDelegate {
    private let home = NSHomeDirectory()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusPath = "/tmp/kinit-refresh.status"
    private lazy var trafficPath = "\(home)/.codex-gcp-tunnel/monitor-latest.env"
    private lazy var refreshScript = "\(home)/bin/kinit-refresh"
    private lazy var stayAwakeScript = "\(home)/bin/stay-awake.sh"
    private lazy var stayAwakePlist = "\(home)/Library/LaunchAgents/com.example.stay-awake.plist"
    private let stayAwakeLabel = "com.example.stay-awake"
    private let stayAwakePidPath = "/tmp/stay-awake.pid"
    private let staleSeconds: TimeInterval = 20 * 60
    private var timer: Timer?
    private let summaryItem = NSMenuItem(title: "刷新状态中...", action: nil, keyEquivalent: "")
    private let refreshGCPItem = NSMenuItem(title: "修复 GCP", action: #selector(refreshRemoteGCP), keyEquivalent: "g")
    private let toggleStayAwakeItem = NSMenuItem(title: "保持唤醒", action: #selector(toggleStayAwake), keyEquivalent: "a")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.addItem(summaryItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(refreshGCPItem)
        menu.addItem(NSMenuItem(title: "刷新 SSH", action: #selector(refreshSSH), keyEquivalent: "r"))
        menu.addItem(toggleStayAwakeItem)
        statusItem.menu = menu
        statusItem.autosaveName = NSStatusItem.AutosaveName("com.example.kinit-refresh-status")
        statusItem.button?.title = "⚪KC"
    }

    private func updateStatus() {
        let data = readStatus()
        let traffic = readTraffic()
        let status = data["STATUS"] ?? "unknown"
        let ssh = data["SSH"] ?? "unknown"
        let proxy = data["PROXY"] ?? "unknown"
        let codex = data["CODEX"] ?? "unknown"
        let exp = data["EXP"] ?? ""
        let message = data["MESSAGE"] ?? "暂无状态"
        let updated = data["UPDATED"] ?? "unknown"
        let updatedEpoch = TimeInterval(data["UPDATED_EPOCH"] ?? "") ?? 0
        let isStale = updatedEpoch == 0 || Date().timeIntervalSince1970 - updatedEpoch > staleSeconds

        let icon: String
        if isStale {
            icon = "🔴"
        } else if status == "ok" && ssh == "ok" && proxy == "ok" && codex == "ok" {
            icon = "🟢"
        } else if status == "stopped" || proxy == "stopped" || codex == "stopped" {
            icon = "⚪"
        } else if status == "ok" && ssh == "ok" && (proxy == "skipped" || codex == "skipped") {
            icon = "⚪"
        } else if status == "running" || status == "warning" {
            icon = "🟡"
        } else {
            icon = "🔴"
        }

        let shortExp = shorten(exp)
        let title = icon + "KC"
        let trafficLabel = trafficSummary(traffic)
        statusItem.button?.title = title
        statusItem.button?.toolTip = "kinit-refresh: \(message) | SSH: \(ssh) | Proxy: \(proxy) | Codex: \(codex) | Exp: \(shortExp) | \(trafficLabel)"

        summaryItem.title = "\(title) | SSH: \(ssh) | \(message)"
        summaryItem.toolTip = "Proxy: \(proxy) | Codex: \(codex) | 更新: \(updated) | \(trafficLabel)"
        refreshGCPItem.title = "修复 GCP    \(trafficLabel)"
        refreshGCPItem.toolTip = trafficTooltip(traffic)

        let awakeRunning = isStayAwakeRunning()
        toggleStayAwakeItem.title = awakeRunning ? "关闭防休眠" : "保持唤醒"
    }

    private func readStatus() -> [String: String] {
        let result = readKeyValueFile(statusPath)
        if result.isEmpty {
            return ["STATUS": "fail", "SSH": "unknown", "MESSAGE": "状态文件不存在, 等待下一次刷新"]
        }
        return result
    }

    private func readTraffic() -> [String: String] {
        return readKeyValueFile(trafficPath)
    }

    private func readKeyValueFile(_ path: String) -> [String: String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let idx = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<idx])
            let value = String(line[line.index(after: idx)...])
            result[key] = value
        }
        return result
    }

    private func trafficSummary(_ traffic: [String: String]) -> String {
        let today = traffic["TRAFFIC_TODAY_HUMAN"] ?? "采样中"
        let day = traffic["TRAFFIC_24H_HUMAN"] ?? "采样中"
        let rate = traffic["TRAFFIC_RATE_HUMAN"] ?? "采样中"
        let status = traffic["TRAFFIC_STATUS"] ?? "unknown"

        let prefix: String
        switch status {
        case "critical":
            prefix = "流量异常"
        case "warning":
            prefix = "流量偏高"
        default:
            prefix = "流量"
        }

        return "\(prefix) 今日 \(today) / 24h \(day) / 当前 \(rate)"
    }

    private func trafficTooltip(_ traffic: [String: String]) -> String {
        let updated = traffic["UPDATED"] ?? "unknown"
        let rate = traffic["TRAFFIC_RATE_HUMAN"] ?? "unknown"
        let iface = traffic["GCP_COUNTER_IFACE"] ?? "unknown"
        let rx = traffic["GCP_RX_BYTES"] ?? "unknown"
        let tx = traffic["GCP_TX_BYTES"] ?? "unknown"
        return "\(trafficSummary(traffic)) | 当前速率 \(rate) | iface \(iface) | RX \(rx) | TX \(tx) | 更新 \(updated)"
    }

    private func shorten(_ exp: String) -> String {
        let parts = exp.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return "\(parts[0])\(parts[1])"
        }
        return exp
    }

    @objc private func refreshSSH() {
        runRefresh(title: "🟡KC", arguments: ["ssh-only"])
    }

    @objc private func refreshRemoteGCP() {
        runRefresh(title: "🟡KC", arguments: ["remote-gcp"])
    }

    private func runRefresh(title: String, arguments: [String]) {
        statusItem.button?.title = title
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: self.refreshScript)
            task.arguments = arguments
            _ = try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
    }

    private func isStayAwakeRunning() -> Bool {
        guard
            let content = try? String(contentsOfFile: stayAwakePidPath, encoding: .utf8),
            let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return false
        }
        return kill(pid, 0) == 0
    }

    @objc private func toggleStayAwake() {
        if isStayAwakeRunning() {
            stopStayAwake()
        } else {
            startStayAwake()
        }
    }

    private func startStayAwake() {
        statusItem.button?.title = "🟡 AWK"
        DispatchQueue.global(qos: .utility).async {
            let domain = "gui/\(getuid())"
            self.runProcess("/bin/launchctl", ["bootstrap", domain, self.stayAwakePlist])
            self.runProcess("/bin/launchctl", ["kickstart", "-k", "\(domain)/\(self.stayAwakeLabel)"])
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
    }

    private func stopStayAwake() {
        statusItem.button?.title = "🟡 AWK"
        DispatchQueue.global(qos: .utility).async {
            let domain = "gui/\(getuid())"
            self.runProcess("/bin/launchctl", ["bootout", domain, self.stayAwakePlist])
            self.runProcess(self.stayAwakeScript, ["stop"])
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
    }

    private func runProcess(_ executable: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
        }
    }
}

let app = NSApplication.shared
let delegate = StatusApp()
app.delegate = delegate
app.run()
