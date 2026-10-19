import Darwin
import Foundation
import AppViewShared
import RxSwift

final class AVSimulatorConnectionPort: CustomStringConvertible {
    var portNumber: Int32 = 0
    var connectedChannel: AVPeerChannel?

    var description: String {
        "number:\(portNumber)"
    }
}

final class AVUSBConnectionPort: CustomStringConvertible {
    var portNumber: Int32 = 0
    var deviceID: NSNumber?
    var connectedChannel: AVPeerChannel?

    var description: String {
        "number:\(portNumber), deviceID:\(String(describing: deviceID)), connectedChannel:\(String(describing: connectedChannel))"
    }
}

extension AVConnectionManager {
    private static var lastIOSRelistenRequestAt: TimeInterval = 0
    private static var bootedSimulatorCache: (value: Bool, at: TimeInterval, count: Int)?
    /// Serializes Peertalk discover connects — concurrent launch poll + MCP refresh raced on
    /// port.connectedChannel / mcpLastConnectSnapshot (SIGSEGV in dual-sim).
    private static let connectAllPortsLock = NSLock()

    static func invalidateBootedSimulatorCache() {
        bootedSimulatorCache = nil
    }

    // MARK: - Ports Connect

    /// Closes all cached discovery transports (launch-screen rescan after leaving inspector).
    public func releaseAllDiscoveryChannels() {
        for port in allSimulatorPorts {
            port.connectedChannel?.close()
            port.connectedChannel = nil
        }
        for port in allUSBPorts {
            port.connectedChannel?.close()
            port.connectedChannel = nil
        }
    }

    /// Closes discovery transports except the target session (USB is unstable while sim link stays open).
    public func releaseDiscoveryChannels(except keep: AVPeerChannel?) {
        var toRelease: [AVPeerChannel] = []
        for port in allSimulatorPorts {
            if let channel = port.connectedChannel, channel !== keep {
                toRelease.append(channel)
            }
        }
        for port in allUSBPorts {
            if let channel = port.connectedChannel, channel !== keep {
                toRelease.append(channel)
            }
        }
        for channel in toRelease {
            releaseCachedChannel(channel)
        }
    }

    /// Clears cached Peertalk channels and closes the transport (e.g. when leaving the inspector).
    public func releaseCachedChannel(_ channel: AVPeerChannel) {
        let wasSimulator = isSimulatorPeertalkPort(channel.targetPort)
        for port in allSimulatorPorts where port.connectedChannel === channel {
            port.connectedChannel = nil
        }
        for port in allUSBPorts where port.connectedChannel === channel {
            port.connectedChannel = nil
        }
        if channel.isConnected {
            channel.cancel()
        } else {
            channel.close()
        }
        if wasSimulator {
            Self.invalidateBootedSimulatorCache()
        }
    }

    private func purgeDisconnectedCachedChannels() async {
        AVConnectionTiming.shared.begin("connect.purge")
        defer { AVConnectionTiming.shared.end("connect.purge") }
        for port in allSimulatorPorts {
            guard let channel = port.connectedChannel else { continue }
            if let async = channel as? AVAsyncPeerChannel {
                await async.reconcileTransportState()
            }
            let portMismatch = channel.targetPort != Int(port.portNumber) && channel.targetPort > 0
            guard !portMismatch, channel.isConnected else {
                channel.close()
                port.connectedChannel = nil
                continue
            }
        }
        for port in allUSBPorts {
            guard let channel = port.connectedChannel else { continue }
            if let async = channel as? AVAsyncPeerChannel {
                await async.reconcileTransportState()
            }
            guard !channel.isConnected else { continue }
            channel.close()
            port.connectedChannel = nil
        }
    }

    /// Drops cached Peertalk transports. Asks iOS to relisten only when MCP is up; the pod already listens after launch.
    /// Returns whether a relisten request was accepted (the new bind is asynchronous).
    @discardableResult
    public func prepareForAppRediscovery() -> Bool {
        Self.invalidateBootedSimulatorCache()
        let relisten = requestIOSPeertalkRelisten()
        releaseAllDiscoveryChannels()
        mcpLastConnectSnapshot = nil
        return relisten
    }

    public func tryToConnectAllPorts(forceFreshDiscovery: Bool = false) -> Single<[AVPeerChannel]> {
        Single.create { single in
            let task = Task { [self] in
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    Self.connectAllPortsLock.lock()
                    cont.resume()
                }
                defer { Self.connectAllPortsLock.unlock() }

                AVConnectionTiming.shared.begin("connect.allPorts", attrs: ["fresh": forceFreshDiscovery])
                defer { AVConnectionTiming.shared.end("connect.allPorts", attrs: ["fresh": forceFreshDiscovery]) }
                // ObjC parity: normal discovery only purges dead transports. Full rediscovery
                // (relisten + close all) is explicit via forceFreshDiscovery — not on every
                // launch poll / auto-reconnect while inspectingApp is nil (breaks USB devices).
                if forceFreshDiscovery {
                    AVConnectionTiming.shared.begin("connect.freshPrepare")
                    let relisten = self.prepareForAppRediscovery()
                    AVConnectionTiming.shared.end("connect.freshPrepare", attrs: ["relisten": relisten])
                    // Wait only after iOS accepted a relisten. A pod that is already listening needs no delay.
                    if relisten {
                        let delayNs: UInt64 = ProcessInfo.processInfo.environment["APPVIEW_VERIFY"] == "1"
                            ? 2_000_000_000
                            : 1_000_000_000
                        try? await Task.sleep(nanoseconds: delayNs)
                    }
                } else {
                    await self.purgeDisconnectedCachedChannels()
                }
                async let simulatorChannels = self.tryConnectAllSimulatorPorts()
                async let usbChannels = self.tryConnectAllUSBDevices()
                let channels = await simulatorChannels + usbChannels
                if !channels.isEmpty, self.mcpLastConnectSnapshot == nil {
                    self.mcpLastConnectSnapshot = AVMCPConnectSnapshot(
                        channelCount: channels.count,
                        connectedPorts: channels.map { Int($0.targetPort) },
                        timestamp: Date().timeIntervalSince1970
                    )
                }
                single(.success(channels))
            }
            return Disposables.create { task.cancel() }
        }
    }

    private struct SimulatorConnectAttempt {
        let portNumber: Int32
        let channel: AVPeerChannel?
        let errnoCode: Int?
    }

    public func mcpCachedSimulatorPortNumbers() -> [Int32] {
        allSimulatorPorts.compactMap { port in
            port.connectedChannel != nil ? port.portNumber : nil
        }
    }

    private func tryConnectAllSimulatorPorts(isRetryAfterIOSRelisten: Bool = false) async -> [AVPeerChannel] {
        AVConnectionTiming.shared.begin("connect.simctlBooted")
        let booted = Self.hasBootedIOSSimulator()
        AVConnectionTiming.shared.end("connect.simctlBooted", attrs: ["booted": booted])
        guard booted else { return [] }

        AVConnectionTiming.shared.begin("connect.simPorts", attrs: ["retry": isRetryAfterIOSRelisten])
        let channels = await performSimulatorConnectAttempts()
        AVConnectionTiming.shared.end(
            "connect.simPorts",
            attrs: ["retry": isRetryAfterIOSRelisten, "count": channels.count]
        )
        if channels.isEmpty, !isRetryAfterIOSRelisten {
            let verifyNoListeners = ProcessInfo.processInfo.environment["APPVIEW_VERIFY"] == "1"
                && simulatorPortsForDiscovery().isEmpty
            let errors = mcpLastConnectSnapshot?.portErrors ?? []
            let allRefused = !errors.isEmpty && errors.allSatisfy { $0.hasSuffix(":61") }
            // :47190 MCP exists only in Simulator (localhost port-forward). Skip on USB-only workflows.
            if verifyNoListeners || allRefused {
                AVConnectionTiming.shared.begin("connect.relisten")
                let relisten = requestIOSPeertalkRelisten()
                AVConnectionTiming.shared.end("connect.relisten", attrs: ["ok": relisten])
                if relisten {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    return await tryConnectAllSimulatorPorts(isRetryAfterIOSRelisten: true)
                }
            }
        }
        return channels
    }

    /// MCP launch-health: whether an iOS Simulator is booted (cached ~3s).
    static func mcpHasBootedIOSSimulator() -> Bool {
        mcpBootedIOSSimulatorCount() > 0
    }

    /// Number of booted iOS simulators (cached ~3s with `bootedSimulatorCache`).
    static func mcpBootedIOSSimulatorCount() -> Int {
        let now = Date().timeIntervalSince1970
        if let cached = bootedSimulatorCache, now - cached.at < 3 {
            return cached.count
        }
        let count = queryBootedIOSSimulatorCount()
        bootedSimulatorCache = (count > 0, now, count)
        return count
    }

    /// Avoid simctl + :47190 relisten spam when the user inspects a physical device only.
    private static func hasBootedIOSSimulator() -> Bool {
        mcpBootedIOSSimulatorCount() > 0
    }

    private static func queryBootedIOSSimulatorCount() -> Int {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["simctl", "list", "devices", "booted", "-j"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        var count = 0
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let devices = json["devices"] as? [String: [[String: Any]]] {
                    for list in devices.values {
                        count += list.filter { ($0["state"] as? String) == "Booted" }.count
                    }
                }
            }
        } catch {
            count = 0
        }
        return count
    }

    private func simulatorPortsForDiscovery() -> [AVSimulatorConnectionPort] {
        let prefilterPorts = ProcessInfo.processInfo.environment["APPVIEW_VERIFY"] == "1"
            || ProcessInfo.processInfo.environment["APPVIEW_CONN_TIMING"] == "1"
        guard prefilterPorts else {
            return allSimulatorPorts
        }
        let listening = allSimulatorPorts.filter {
            AVMCPClientDiagnostics.simulatorPortIsListening(Int($0.portNumber))
        }
        // Do not parallel-scan the full port range — stray connects break iOS Peertalk.
        // When multiple simulators run demos, each binds a distinct LISTEN port — connect to all of them.
        if AVConnectionTiming.isEnabled, !listening.isEmpty {
            let portList = listening.map { Int($0.portNumber) }.sorted()
            AVConnectionTiming.shared.recordInstant(
                "connect.listeningPorts",
                durationMs: 0,
                attrs: ["ports": portList, "count": portList.count]
            )
        }
        return listening
    }

    private func performSimulatorConnectAttempts() async -> [AVPeerChannel] {
        let ports = simulatorPortsForDiscovery()
        return await withTaskGroup(of: SimulatorConnectAttempt.self) { group in
            for port in ports {
                group.addTask { [self] in
                    do {
                        let channel = try await connectToSimulatorPort(port)
                        return SimulatorConnectAttempt(portNumber: port.portNumber, channel: channel, errnoCode: nil)
                    } catch {
                        return SimulatorConnectAttempt(
                            portNumber: port.portNumber,
                            channel: nil,
                            errnoCode: (error as NSError).code
                        )
                    }
                }
            }
            var channels: [AVPeerChannel] = []
            var connectErrors: [String] = []
            var connectedPorts: [Int] = []
            for await attempt in group {
                if let channel = attempt.channel {
                    channels.append(channel)
                    connectedPorts.append(Int(attempt.portNumber))
                } else if let code = attempt.errnoCode {
                    connectErrors.append("\(attempt.portNumber):\(code)")
                }
            }

            let snapshot = AVMCPConnectSnapshot(
                channelCount: channels.count,
                connectedPorts: connectedPorts,
                portErrors: connectErrors,
                cachedSimulatorPorts: allSimulatorPorts
                    .filter { $0.connectedChannel != nil }
                    .map { Int($0.portNumber) },
                timestamp: Date().timeIntervalSince1970
            )
            mcpLastConnectSnapshot = snapshot
            AVMCPClientDiagnostics.shared.recordConnectSnapshot(snapshot)

            if channels.isEmpty {
                let summary = connectErrors.isEmpty
                    ? "all ports failed (no errno captured)"
                    : connectErrors.joined(separator: " ")
                let allRefused = !connectErrors.isEmpty && connectErrors.allSatisfy { $0.hasSuffix(":61") }
                AppViewDiagLog.log(
                    "client connect simulator channels=0 errors=[\(summary)] (61=ECONNREFUSED — start AppViewCustomInfoDemo in Simulator; 48=EADDRINUSE on iOS — kill stale demo)"
                )
                if allRefused {
                    AppViewDiagLog.log(
                        "client hint: run the iOS app with the AppViewServer pod — it listens on Peertalk without an extra call. Bring Simulator to front."
                    )
                }
            } else {
                let ports = channels.map { String($0.targetPort) }.joined(separator: ",")
                AppViewDiagLog.log("client connect simulator channels=\(channels.count) ports=[\(ports)]")
            }
            return channels
        }
    }

    /// Ask the running Simulator app (MCP :47190) to drop a stale Peertalk peer and listen again.
    private func requestIOSPeertalkRelisten() -> Bool {
        guard Self.hasBootedIOSSimulator() else { return false }

        let now = Date().timeIntervalSince1970
        guard now - Self.lastIOSRelistenRequestAt >= 2 else { return false }
        Self.lastIOSRelistenRequestAt = now

        if performIOSMCPRequest(method: "POST", path: "/relisten-peertalk") {
            AppViewDiagLog.log("client POST iOS /relisten-peertalk OK — will retry simulator connect")
            return true
        }
        // Older demo builds: GET /status nudges `nudgePeertalkListenForLaunchScreenDiscoveryIfNeeded`.
        if performIOSMCPRequest(method: "GET", path: "/status") {
            AppViewDiagLog.log("client GET iOS /status — nudged Peertalk re-listen before discovery")
            return true
        }
        return false
    }

    private func performIOSMCPRequest(method: String, path: String) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:47190\(path)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 2

        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error == nil, let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) {
                succeeded = true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return succeeded
    }

    private func connectToSimulatorPort(_ port: AVSimulatorConnectionPort) async throws -> AVPeerChannel {
        if let connectedChannel = port.connectedChannel {
            if let async = connectedChannel as? AVAsyncPeerChannel {
                await async.reconcileTransportState()
            }
            let portMatches = connectedChannel.targetPort == Int(port.portNumber)
            if connectedChannel.isConnected, portMatches {
                return connectedChannel
            }
            connectedChannel.close()
            port.connectedChannel = nil
        }

        let wrapper = AVAsyncPeerChannel(manager: self)
        try await wrapper.connect(toPort: UInt16(port.portNumber))
        port.connectedChannel = wrapper
        return wrapper
    }

    private func tryConnectAllUSBDevices() async -> [AVPeerChannel] {
        guard !allUSBPorts.isEmpty else {
            AppViewDiagLog.log("client connect usb channels=0 (no USB device in allUSBPorts — plug in device or unlock iPhone)")
            return []
        }

        // iOS binds Peertalk asynchronously after scene/active — retry before giving up this poll.
        let maxAttempts = 6
        for attempt in 1 ... maxAttempts {
            let channels = await performUSBConnectAttempts()
            if !channels.isEmpty {
                let ports = channels.map { String($0.targetPort) }.joined(separator: ",")
                AppViewDiagLog.log("client connect usb channels=\(channels.count) ports=[\(ports)]")
                return channels
            }
            if attempt < maxAttempts {
                // iOS Peertalk watchdog may need ~1s to recycle after Mac AppView quit (killall).
                let delayMs: UInt64 = attempt == 3 ? 2_000_000_000 : 900_000_000
                try? await Task.sleep(nanoseconds: delayMs)
            }
        }
        return []
    }

    private func performUSBConnectAttempts() async -> [AVPeerChannel] {
        await withTaskGroup(of: (Int32, AVPeerChannel?, Int?).self) { group in
            for port in allUSBPorts {
                group.addTask { [self] in
                    do {
                        let channel = try await connectToUSBPort(port)
                        return (port.portNumber, channel, nil)
                    } catch {
                        return (port.portNumber, nil, (error as NSError).code)
                    }
                }
            }
            var channels: [AVPeerChannel] = []
            var connectErrors: [String] = []
            for await attempt in group {
                if let channel = attempt.1 {
                    channels.append(channel)
                } else if let code = attempt.2 {
                    connectErrors.append("\(attempt.0):\(code)")
                }
            }
            if channels.isEmpty {
                let summary = connectErrors.isEmpty
                    ? "all USB ports failed (no errno captured)"
                    : connectErrors.joined(separator: " ")
                AppViewDiagLog.log(
                    "client connect usb channels=0 devicePorts=\(allUSBPorts.count) errors=[\(summary)] (3=connection refused — on iPhone Xcode console expect 'Connected successfully on 127.0.0.1:4717x'; rebuild demo after pod install)"
                )
            }
            return channels
        }
    }

    private func connectToUSBPort(_ port: AVUSBConnectionPort) async throws -> AVPeerChannel {
        if let connectedChannel = port.connectedChannel {
            if let async = connectedChannel as? AVAsyncPeerChannel {
                await async.reconcileTransportState()
            }
            let portMatches = connectedChannel.targetPort == Int(port.portNumber)
            if connectedChannel.isConnected, portMatches {
                return connectedChannel
            }
            connectedChannel.close()
            port.connectedChannel = nil
        }

        guard let deviceID = port.deviceID else {
            throw AVAppViewClientErrors.inner
        }

        let wrapper = AVAsyncPeerChannel(manager: self)
        try await wrapper.connect(
            toPort: port.portNumber,
            over: AppViewPTUSBHub.shared(),
            deviceID: deviceID
        )
        port.connectedChannel = wrapper
        return wrapper
    }

    // MARK: - USB Device Listening

    func startListeningForUSBDevices() {
        let center = NotificationCenter.default
        // Observers must exist before sharedHub starts usbmux Listen — otherwise
        // Attached for an already-plugged iPhone is delivered before registration.
        center.addObserver(
            forName: NSNotification.Name(AppView_PTUSBDeviceDidAttachNotification),
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.registerUSBDevice(fromAttachNotification: note)
        }

        center.addObserver(
            forName: NSNotification.Name(AppView_PTUSBDeviceDidDetachNotification),
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let self, let deviceID = self.usbDeviceID(from: note) else { return }
            self.allUSBPorts.removeAll { $0.deviceID == deviceID }
            self.attachedUSBDeviceLabels.removeValue(forKey: deviceID.uint32Value)
            NSLog("AppView - USB 设备拔出，DeviceID: %@", deviceID)
        }

        _ = AppViewPTUSBHub.shared()
    }

    private func usbDeviceID(from note: Notification) -> NSNumber? {
        guard let raw = note.userInfo?["DeviceID"] else { return nil }
        if let id = raw as? NSNumber { return id }
        if let id = raw as? Int { return NSNumber(value: id) }
        if let id = raw as? UInt32 { return NSNumber(value: id) }
        if let id = raw as? Int64 { return NSNumber(value: id) }
        return nil
    }

    private func usbDeviceLabel(from note: Notification) -> String? {
        guard let props = note.userInfo?["Properties"] as? [String: Any] else { return nil }
        if let name = props["DeviceName"] as? String, !name.isEmpty {
            return name
        }
        if let serial = props["SerialNumber"] as? String, !serial.isEmpty, !looksLikeUDID(serial) {
            return serial
        }
        return nil
    }

    private func looksLikeUDID(_ value: String) -> Bool {
        value.count >= 20 && value.contains("-")
    }

    private func registerUSBDevice(fromAttachNotification note: Notification) {
        guard let deviceID = usbDeviceID(from: note) else {
            AppViewDiagLog.log("client USB attach ignored — missing DeviceID in notification")
            return
        }
        if let label = usbDeviceLabel(from: note) {
            attachedUSBDeviceLabels[deviceID.uint32Value] = label
        }
        if allUSBPorts.contains(where: { $0.deviceID == deviceID }) {
            return
        }
        for number in Int32(AppViewUSBDeviceIPv4PortNumberStart) ... Int32(AppViewUSBDeviceIPv4PortNumberEnd) {
            let port = AVUSBConnectionPort()
            port.portNumber = number
            port.deviceID = deviceID
            allUSBPorts.append(port)
        }
        let label = attachedUSBDeviceLabels[deviceID.uint32Value] ?? "iPhone"
        AppViewDiagLog.log("client USB device attached id=\(deviceID) name=\(label)")
        NSLog("AppView - USB device connected, DeviceID: %@", deviceID)
    }
}
