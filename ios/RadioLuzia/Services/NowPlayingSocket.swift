import Foundation

actor NowPlayingSocket {
    typealias Handler = @MainActor @Sendable (NowPlaying) -> Void

    private let url = URL(string: "wss://webradio.cloudbr.app/api/live/nowplaying/websocket")!
    private let decoder = JSONDecoder()
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var intentionallyStopped = false

    func connect(onUpdate: @escaping Handler) {
        intentionallyStopped = false
        open(onUpdate: onUpdate)
    }

    func disconnect() {
        intentionallyStopped = true
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func open(onUpdate: @escaping Handler) {
        receiveTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        let socket = URLSession.shared.webSocketTask(with: url)
        task = socket
        socket.resume()

        let subscription = #"{"subs":{"station:santaluziapgm":{"recover":true}}}"#
        socket.send(.string(subscription)) { [weak self] error in
            guard error != nil else { return }
            Task { await self?.scheduleReconnect(onUpdate: onUpdate) }
        }

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(socket: socket, onUpdate: onUpdate)
        }
    }

    private func receiveLoop(socket: URLSessionWebSocketTask, onUpdate: @escaping Handler) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                reconnectAttempt = 0
                for payload in extractPayloads(from: data) {
                    if let model = try? decoder.decode(NowPlaying.self, from: payload) {
                        await onUpdate(model)
                    }
                }
            }
        } catch {
            await scheduleReconnect(onUpdate: onUpdate)
        }
    }

    private func extractPayloads(from data: Data) -> [Data] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            !root.isEmpty
        else { return [] }

        var results: [Data] = []
        func appendNP(from publication: [String: Any]) {
            guard
                let wrapper = publication["data"] as? [String: Any],
                let np = wrapper["np"],
                JSONSerialization.isValidJSONObject(np),
                let encoded = try? JSONSerialization.data(withJSONObject: np)
            else { return }
            results.append(encoded)
        }

        if let publication = root["pub"] as? [String: Any] { appendNP(from: publication) }
        if let connect = root["connect"] as? [String: Any] {
            if let legacyRows = connect["data"] as? [[String: Any]] {
                legacyRows.forEach(appendNP)
            }
            if let subscriptions = connect["subs"] as? [String: [String: Any]] {
                for subscription in subscriptions.values {
                    (subscription["publications"] as? [[String: Any]])?.forEach(appendNP)
                }
            }
        }
        return results
    }

    private func scheduleReconnect(onUpdate: @escaping Handler) async {
        guard !intentionallyStopped else { return }
        task = nil
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30)
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled, !intentionallyStopped else { return }
        open(onUpdate: onUpdate)
    }
}

