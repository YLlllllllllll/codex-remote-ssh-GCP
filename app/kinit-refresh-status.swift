import AppKit
import Foundation

final class StatusApp: NSObject, NSApplicationDelegate {
    private let home = NSHomeDirectory()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusPath = "/tmp/kinit-refresh.status"
    private lazy var refreshScript = "\(home)/bin/kinit-refresh"
    private lazy var stayAwakeScript = "\(home)/bin/stay-awake.sh"
    private lazy var stayAwakePlist = "\(home)/Library/LaunchAgents/com.example.stay-awake.plist"
    private let stayAwakeLabel = "com.example.stay-awake"
    private let stayAwakePidPath = "/tmp/stay-awake.pid"
    private let staleSeconds: TimeInterval = 20 * 60
    private var timer: Timer?
    private let summaryItem = NSMenuItem(title: "刷新状态中...", action: nil, keyEquivalent: "")
    private let codexItem = NSMenuItem(title: "Codex: unknown | Proxy: unknown", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "更新: unknown", action: nil, keyEquivalent: "")
    private let stayAwakeItem = NSMenuItem(title: "防休眠: unknown", action: nil, keyEquivalent: "")
    private let startStayAwakeItem = NSMenuItem(title: "开启防休眠", action: #selector(startStayAwake), keyEquivalent: "a")
    private let stopStayAwakeItem = NSMenuItem(title: "停止防休眠", action: #selector(stopStayAwake), keyEquivalent: "s")

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
        menu.addItem(codexItem)
        menu.addItem(updatedItem)
        menu.addItem(stayAwakeItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "刷新 SSH", action: #selector(refreshSSH), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "刷新 Remote GCP", action: #selector(refreshRemoteGCP), keyEquivalent: "g"))
        menu.addItem(NSMenuItem(title: "完整验证 Remote GCP", action: #selector(refreshRemoteGCPFull), keyEquivalent: "f"))
        menu.addItem(startStayAwakeItem)
        menu.addItem(stopStayAwakeItem)
        menu.addItem(NSMenuItem(title: "打开日志", action: #selector(openLog), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出状态栏", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.autosaveName = NSStatusItem.AutosaveName("com.example.kinit-refresh-status")
        statusItem.button?.title = "⚪KC"
    }

    private func updateStatus() {
        let data = readStatus()
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
        let proxySatisfied = proxy == "ok" || proxy == "skipped"
        let codexSatisfied = codex == "ok" || codex == "skipped"

        if isStale {
            icon = "🔴"
        } else if status == "ok" && ssh == "ok" && proxySatisfied && codexSatisfied {
            icon = "🟢"
        } else if status == "running" || status == "warning" {
            icon = "🟡"
        } else {
            icon = "🔴"
        }

        let shortExp = shorten(exp)
        let title = icon + "KC"
        statusItem.button?.title = title
        statusItem.button?.toolTip = "kinit-refresh: \(message) | SSH: \(ssh) | Proxy: \(proxy) | Codex: \(codex) | Exp: \(shortExp)"

        summaryItem.title = "\(title) | SSH: \(ssh) | \(message)"
        codexItem.title = "Codex: \(codex) | Proxy: \(proxy)"
        updatedItem.title = "更新: \(updated)"

        let awakeRunning = isStayAwakeRunning()
        stayAwakeItem.title = awakeRunning ? "防休眠: 开启" : "防休眠: 停止"
        startStayAwakeItem.isEnabled = !awakeRunning
        stopStayAwakeItem.isEnabled = awakeRunning
    }

    private func readStatus() -> [String: String] {
        guard let content = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            return ["STATUS": "fail", "SSH": "unknown", "MESSAGE": "状态文件不存在, 等待下一次刷新"]
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

    @objc private func refreshRemoteGCPFull() {
        runRefresh(title: "🟡KC", arguments: ["remote-gcp-full"])
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

    @objc private func startStayAwake() {
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

    @objc private func stopStayAwake() {
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

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/kinit-refresh.log"))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = StatusApp()
app.delegate = delegate
app.run()
