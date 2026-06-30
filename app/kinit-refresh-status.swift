import AppKit
import Foundation

private struct TicketInfo {
    let expiration: String
    let renewUntil: String?
}

final class StatusApp: NSObject, NSApplicationDelegate {
    private let home = NSHomeDirectory()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusPath = "/tmp/kinit-refresh.status"
    private lazy var trafficPath = "\(home)/.codex-gcp-tunnel/monitor-latest.env"
    private lazy var sessionsPath = "\(home)/.codex-gcp-tunnel/active-sessions.txt"
    private lazy var refreshScript = "\(home)/bin/kinit-refresh"
    private lazy var gcpRemoteScript = "\(home)/bin/codex-gcp-remote"
    private lazy var autohealScript = "\(home)/bin/codex-gcp-autoheal"
    private lazy var cursorResetScript = "\(home)/bin/cursor-remote-reset"
    private lazy var gcpStateDir = "\(home)/.codex-gcp-tunnel"
    private lazy var gcpDiagnoseLogPath = "\(home)/.codex-gcp-tunnel/gcp-diagnose-latest.log"
    private lazy var autohealStatusLogPath = "\(home)/.codex-gcp-tunnel/autoheal-status-latest.log"
    private lazy var stayAwakeScript = "\(home)/bin/stay-awake.sh"
    private lazy var stayAwakePlist = "\(home)/Library/LaunchAgents/com.example.stay-awake.plist"
    private let stayAwakeLabel = "com.example.stay-awake"
    private let stayAwakePidPath = "/tmp/stay-awake.pid"
    private let staleSeconds: TimeInterval = 20 * 60
    private var timer: Timer?
    private let summaryItem = NSMenuItem(title: "刷新状态中...", action: nil, keyEquivalent: "")
    private let refreshGCPItem = NSMenuItem(title: "修复 GCP", action: #selector(refreshRemoteGCP), keyEquivalent: "g")
    private let verifyGCPItem = NSMenuItem(title: "验证 GCP", action: #selector(verifyGCP), keyEquivalent: "v")
    private let diagnoseGCPItem = NSMenuItem(title: "诊断 GCP", action: #selector(diagnoseGCP), keyEquivalent: "d")
    private let autohealGCPItem = NSMenuItem(title: "触发 Auto-Heal", action: #selector(triggerAutoheal), keyEquivalent: "h")
    private let autohealStatusItem = NSMenuItem(title: "查看 Auto-Heal 状态", action: #selector(showAutohealStatus), keyEquivalent: "")
    private let sessionsItem = NSMenuItem(title: "Codex Sessions: 采样中", action: nil, keyEquivalent: "")
    private let sessionsMenu = NSMenu(title: "Codex Sessions")
    private let kinitLoginItem = NSMenuItem(title: "登录/更新 kinit", action: #selector(loginKinit), keyEquivalent: "k")
    private let resetCursorItem = NSMenuItem(title: "重置 Cursor SSH", action: #selector(resetCursorSSH), keyEquivalent: "u")
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
        menu.addItem(verifyGCPItem)
        menu.addItem(diagnoseGCPItem)
        menu.addItem(autohealGCPItem)
        menu.addItem(autohealStatusItem)
        sessionsItem.submenu = sessionsMenu
        menu.addItem(sessionsItem)
        menu.addItem(kinitLoginItem)
        menu.addItem(NSMenuItem(title: "刷新 SSH", action: #selector(refreshSSH), keyEquivalent: "r"))
        menu.addItem(resetCursorItem)
        menu.addItem(toggleStayAwakeItem)
        statusItem.menu = menu
        statusItem.autosaveName = NSStatusItem.AutosaveName("com.example.kinit-refresh-status")
        statusItem.button?.title = "⚪KC"
        statusItem.isVisible = true
    }

    private func updateStatus() {
        let data = readStatus()
        let traffic = readTraffic()
        let sessions = readSessions()
        let status = data["STATUS"] ?? "unknown"
        let ssh = data["SSH"] ?? "unknown"
        let proxy = data["PROXY"] ?? "unknown"
        let codex = data["CODEX"] ?? "unknown"
        let message = data["MESSAGE"] ?? "暂无状态"
        let updated = data["UPDATED"] ?? "unknown"
        let updatedEpoch = TimeInterval(data["UPDATED_EPOCH"] ?? "") ?? 0
        let isStale = updatedEpoch == 0 || Date().timeIntervalSince1970 - updatedEpoch > staleSeconds
        let liveTicket = currentTicketInfo()
        let fileExp = data["EXP"] ?? ""
        let exp = liveTicket?.expiration ?? (isStale ? "" : fileExp)
        let renewUntil = liveTicket?.renewUntil
        let monitorGcpOk = traffic["STATUS"] == "ok"
            && traffic["LOCAL_1080_COUNT"] != "0"
            && traffic["LOCAL_7890_COUNT"] != "0"
            && traffic["REMOTE_10800_COUNT"] != "0"

        let icon: String
        if isStale {
            icon = "🔴"
        } else if status == "ok" && ssh == "ok" && (proxy == "ok" && codex == "ok" || monitorGcpOk) {
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

        let shortExp = shortExpiration(exp)
        let shortRenew = shortExpiration(renewUntil ?? "")
        let longExp = longExpiration(exp)
        let longRenew = longRenewal(renewUntil)
        let kinitLabel = [longExp, longRenew].filter { !$0.isEmpty }.joined(separator: "; ")
        let title = icon + "KC"
        let detailTitle = title + (shortExp.isEmpty ? "" : " \(shortExp)") + (shortRenew.isEmpty ? "" : "→\(shortRenew)")
        let trafficLabel = trafficSummary(traffic)
        statusItem.button?.title = title
        statusItem.button?.toolTip = "kinit-refresh: \(message) | Kinit: \(kinitLabel) | SSH: \(ssh) | Proxy: \(proxy) | Codex: \(codex) | \(trafficLabel)"

        let gcpState = monitorGcpOk ? "GCP 可用" : message
        summaryItem.title = "\(detailTitle) | Kinit: \(kinitLabel) | SSH: \(ssh) | \(gcpState)"
        summaryItem.toolTip = "Proxy: \(proxy) | Codex: \(codex) | 更新: \(updated) | \(trafficLabel)"
        refreshGCPItem.title = "修复 GCP    \(trafficLabel)"
        refreshGCPItem.toolTip = trafficTooltip(traffic)
        verifyGCPItem.toolTip = "只验证本地 1080/7890、远程 10800、GCP 出口 IP 和 ChatGPT Codex endpoint，不重建链路"
        diagnoseGCPItem.toolTip = "输出本地监听、远程 10800、Codex wrapper、app-server 环境和最近日志到 \(gcpDiagnoseLogPath)"
        autohealGCPItem.toolTip = "立即运行一轮 codex-gcp-autoheal；只有满足连续失败、冷却窗口等条件时才会触发修复"
        autohealStatusItem.toolTip = "查看 auto-heal 最近决策和日志尾部"
        kinitLoginItem.toolTip = "输入一次 Kerberos 密码并保存到 macOS Keychain；之后刷新 SSH 会自动执行 kinit"
        resetCursorItem.toolTip = "只重置 Cursor Remote SSH 的本地 ssh 隧道，不退出 Cursor 主应用"
        updateSessionsMenu(traffic: traffic, sessions: sessions)

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

    private func readSessions() -> String {
        return (try? String(contentsOfFile: sessionsPath, encoding: .utf8)) ?? ""
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
            prefix = "本地流量异常"
        case "warning":
            prefix = "本地流量偏高"
        default:
            prefix = "本地流量"
        }

        return "\(prefix) 今日 \(today) / 24h \(day) / 当前 \(rate)"
    }

    private func trafficTooltip(_ traffic: [String: String]) -> String {
        let updated = traffic["UPDATED"] ?? "unknown"
        let rate = traffic["TRAFFIC_RATE_HUMAN"] ?? "unknown"
        let iface = traffic["GCP_COUNTER_IFACE"] ?? "unknown"
        let rx = traffic["GCP_RX_BYTES"] ?? "unknown"
        let tx = traffic["GCP_TX_BYTES"] ?? "unknown"
        return "\(trafficSummary(traffic)) | 当前速率 \(rate) | iface \(iface) | RX \(rx) | TX \(tx) | 更新 \(updated) | 本地采样, 不是账单明细"
    }

    private func updateSessionsMenu(traffic: [String: String], sessions: String) {
        let execCount = traffic["REMOTE_CODEX_EXEC_COUNT"] ?? "?"
        let socketCount = traffic["REMOTE_10800_SOCKET_COUNT"] ?? "?"
        let appServerCount = traffic["REMOTE_APP_SERVER_COUNT"] ?? "?"
        let updated = traffic["UPDATED"] ?? "unknown"

        sessionsItem.title = "Codex Sessions: \(execCount)    10800连接 \(socketCount)"
        sessionsItem.toolTip = "远端 codex exec: \(execCount) | 10800 连接: \(socketCount) | app-server: \(appServerCount) | 更新: \(updated)"

        sessionsMenu.removeAllItems()
        sessionsMenu.addItem(NSMenuItem(title: "codex exec: \(execCount) | 10800连接: \(socketCount) | app-server: \(appServerCount)", action: nil, keyEquivalent: ""))
        sessionsMenu.addItem(NSMenuItem(title: "更新: \(updated)", action: nil, keyEquivalent: ""))
        sessionsMenu.addItem(NSMenuItem.separator())

        let detailLines = sessions
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix("UPDATED=") && !$0.hasPrefix("REMOTE_") && !$0.hasPrefix("REMOTE_HOST=") }

        if detailLines.isEmpty {
            sessionsMenu.addItem(NSMenuItem(title: "等待 monitor 采样", action: nil, keyEquivalent: ""))
        } else {
            for line in detailLines.prefix(12) {
                sessionsMenu.addItem(NSMenuItem(title: abbreviate(line, maxLength: 96), action: nil, keyEquivalent: ""))
            }
            if detailLines.count > 12 {
                sessionsMenu.addItem(NSMenuItem(title: "还有 \(detailLines.count - 12) 行，打开详情日志查看", action: nil, keyEquivalent: ""))
            }
        }

        sessionsMenu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "打开详情日志", action: #selector(openSessionsLog), keyEquivalent: "o")
        openItem.target = self
        sessionsMenu.addItem(openItem)
        let copyItem = NSMenuItem(title: "复制详情", action: #selector(copySessionsLog), keyEquivalent: "c")
        copyItem.target = self
        sessionsMenu.addItem(copyItem)
    }

    private func abbreviate(_ value: String, maxLength: Int) -> String {
        if value.count <= maxLength {
            return value
        }
        let end = value.index(value.startIndex, offsetBy: maxLength - 1)
        return String(value[..<end]) + "..."
    }

    private func currentTicketInfo() -> TicketInfo? {
        if let info = currentTicketInfoFromVerboseKlist() {
            return info
        }
        guard let expiration = currentTicketExpirationFromKlist() else {
            return nil
        }
        return TicketInfo(expiration: expiration, renewUntil: nil)
    }

    private func currentTicketInfoFromVerboseKlist() -> TicketInfo? {
        guard let output = runKlist(arguments: ["-v"]) else {
            return nil
        }

        var inTgtBlock = false
        var expiration: String?
        var renewUntil: String?

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Server: ") {
                inTgtBlock = line.contains("krbtgt/")
                continue
            }
            guard inTgtBlock else { continue }

            if line.hasPrefix("End time:") {
                expiration = String(line.dropFirst("End time:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("Renew till:") {
                renewUntil = String(line.dropFirst("Renew till:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let expiration else {
            return nil
        }
        return TicketInfo(expiration: expiration, renewUntil: renewUntil)
    }

    private func currentTicketExpirationFromKlist() -> String? {
        guard let output = runKlist(arguments: []) else {
            return nil
        }

        for line in output.split(separator: "\n") {
            guard line.contains("krbtgt/") else { continue }
            let parts = line.split { $0 == " " || $0 == "\t" }.map(String.init)
            if parts.count >= 8 {
                return "\(parts[4]) \(parts[5]) \(parts[6]) \(parts[7])"
            }
        }

        return nil
    }

    private func runKlist(arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/klist")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func shortExpiration(_ exp: String) -> String {
        guard !exp.isEmpty else { return "" }
        if let date = parseExpiration(exp) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }

        let parts = exp.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return "\(parts[0])\(parts[1])"
        }
        return exp
    }

    private func longExpiration(_ exp: String) -> String {
        guard !exp.isEmpty else { return "未检测到有效票据" }
        if let date = parseExpiration(exp) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return "到 \(formatter.string(from: date))"
        }
        return "到 \(exp)"
    }

    private func longRenewal(_ renew: String?) -> String {
        guard let renew, !renew.isEmpty else { return "" }
        if let date = parseExpiration(renew) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return "可续到 \(formatter.string(from: date))"
        }
        return "可续到 \(renew)"
    }

    private func parseExpiration(_ exp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy"
        return formatter.date(from: exp)
    }

    @objc private func refreshSSH() {
        runRefresh(title: "🟡KC", arguments: ["ssh-only"])
    }

    @objc private func refreshRemoteGCP() {
        runRefresh(title: "🟡KC", arguments: ["remote-gcp"])
    }

    @objc private func verifyGCP() {
        runCommand(title: "🟡KC", executable: gcpRemoteScript, arguments: ["verify-fast"])
    }

    @objc private func diagnoseGCP() {
        runCommand(
            title: "🟡KC",
            executable: gcpRemoteScript,
            arguments: ["diagnose"],
            outputPath: gcpDiagnoseLogPath,
            openOutput: true
        )
    }

    @objc private func triggerAutoheal() {
        runCommand(title: "🟡KC", executable: autohealScript, arguments: ["run"])
    }

    @objc private func showAutohealStatus() {
        runCommand(
            title: "🟡KC",
            executable: autohealScript,
            arguments: ["status"],
            outputPath: autohealStatusLogPath,
            openOutput: true
        )
    }

    @objc private func resetCursorSSH() {
        statusItem.button?.title = "🟡KC"
        DispatchQueue.global(qos: .utility).async {
            self.runProcess(self.cursorResetScript, [])
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
    }

    @objc private func loginKinit() {
        statusItem.button?.title = "🟡KC"
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: self.refreshScript)
            task.arguments = ["save-password"]
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    self.runProcess(self.refreshScript, ["ssh-only"])
                }
            } catch {
            }
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
    }

    @objc private func openSessionsLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: sessionsPath))
    }

    @objc private func copySessionsLog() {
        let content = readSessions()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }

    private func runRefresh(title: String, arguments: [String]) {
        runCommand(title: title, executable: refreshScript, arguments: arguments)
    }

    private func runCommand(
        title: String,
        executable: String,
        arguments: [String],
        outputPath: String? = nil,
        openOutput: Bool = false
    ) {
        statusItem.button?.title = title
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            var outputHandle: FileHandle?

            if let outputPath {
                try? FileManager.default.createDirectory(
                    atPath: self.gcpStateDir,
                    withIntermediateDirectories: true
                )
                FileManager.default.createFile(atPath: outputPath, contents: nil)
                outputHandle = FileHandle(forWritingAtPath: outputPath)
                task.standardOutput = outputHandle ?? FileHandle.nullDevice
                task.standardError = outputHandle ?? FileHandle.nullDevice
            }

            _ = try? task.run()
            task.waitUntilExit()
            try? outputHandle?.close()
            DispatchQueue.main.async {
                self.updateStatus()
                if openOutput, let outputPath {
                    NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
                }
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
