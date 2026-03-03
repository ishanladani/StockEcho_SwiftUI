//
//  WebSocketManager.swift
//  WebSocketManager
//
//  Created by ISHAN LADANI on 27/02/26.
//


import Foundation
import Combine

public final class WebSocketManager: WebSocketManaging {
    public static let shared = WebSocketManager(url: URL(string: "wss://ws.postman-echo.com/raw")!)

    public private(set) var isConnected: Bool = false
    public var messagePublisher: AnyPublisher<String, Never> { messageSubject.eraseToAnyPublisher() }

    private let url: URL
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "com.stocklivetracker.websocket", qos: .userInitiated)

    private let messageSubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()

    private var outgoingBuffer: [String] = []

    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 30

    private var pingTimer: AnyCancellable?

    private let lock = NSLock()

    public init(url: URL, session: URLSession? = nil) {
        self.url = url
        let config = session?.configuration ?? URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = session ?? URLSession(configuration: config)
    }

    deinit {
        disconnect()
        pingTimer?.cancel()
    }

    // MARK: - WebSocketManaging
    public func connect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.webSocketTask == nil else {
                // Already created a task; ensure it's running
                return
            }

            let task = self.session.webSocketTask(with: self.url)
            self.webSocketTask = task
            task.resume()
            self.isConnected = true
            self.reconnectAttempts = 0

            self.drainOutgoingBuffer()

            self.receive()

            self.startPing()
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard let task = self.webSocketTask else { return }
            task.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.isConnected = false
            self.pingTimer?.cancel()
            self.pingTimer = nil
        }
    }

    public func send(_ text: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard let task = self.webSocketTask else {
                // Buffer outgoing message until connected
                self.outgoingBuffer.append(text)
                // Try to connect proactively
                self.connect()
                return
            }
            task.send(.string(text)) { [weak self] error in
                if let error = error {
                    // If send fails, buffer the message and attempt a reconnect
                    self?.queue.async {
                        self?.lock.lock(); defer { self?.lock.unlock() }
                        self?.outgoingBuffer.append(text)
                        self?.handleSendError(error)
                    }
                }
            }
        }
    }

    private func receive() {
        queue.async { [weak self] in
            guard let self = self, let task = self.webSocketTask else { return }
            task.receive { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    // Handle failure and try to reconnect
                    self.handleReceiveError(error)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.messageSubject.send(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.messageSubject.send(text)
                        }
                    @unknown default:
                        break
                    }

                    // Continue receiving
                    self.receive()
                }
            }
        }
    }

    // MARK: - Error handling & reconnect
    private func handleReceiveError(_ error: Error) {
        // Tear down the current task
        lock.lock(); defer { lock.unlock() }
        webSocketTask = nil
        isConnected = false
        pingTimer?.cancel()
        pingTimer = nil

        // Reconnect with backoff
        reconnectWithBackoff()
    }

    private func handleSendError(_ error: Error) {
        // Close and reconnect
        lock.lock(); defer { lock.unlock() }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        pingTimer?.cancel()
        pingTimer = nil

        reconnectWithBackoff()
    }

    private func reconnectWithBackoff() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.connect()
        }
    }

    private func drainOutgoingBuffer() {
        lock.lock()
        let buffer = outgoingBuffer
        outgoingBuffer.removeAll()
        lock.unlock()

        for message in buffer {
            send(message)
        }
    }

    private func startPing() {
        // Send a ping every 15 seconds to keep the connection alive
        pingTimer?.cancel()
        pingTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendPing()
            }
    }

    private func sendPing() {
        queue.async { [weak self] in
            guard let self = self, let task = self.webSocketTask else { return }
            task.sendPing { [weak self] error in
                if let _ = error {
                    // Ping failed; trigger reconnect
                    self?.queue.async {
                        self?.lock.lock(); defer { self?.lock.unlock() }
                        self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        self?.webSocketTask = nil
                        self?.isConnected = false
                        self?.pingTimer?.cancel()
                        self?.pingTimer = nil
                        self?.reconnectWithBackoff()
                    }
                }
            }
        }
    }
}
