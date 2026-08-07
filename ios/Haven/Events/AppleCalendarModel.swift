import Foundation
import SwiftUI

enum AppleCalendarAccess: Equatable, Sendable {
    case notDetermined
    case fullAccess
    case denied
}

protocol AppleCalendarProviding: Sendable {
    func accessStatus() async -> AppleCalendarAccess
    func requestFullAccess() async throws -> AppleCalendarAccess
    func nearbyEvents(around date: Date) async throws -> [CalendarEventCandidate]
}

@MainActor
final class AppleCalendarModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case needsPermission
        case ready([CalendarEventCandidate])
        case denied
        case failed
    }

    @Published private(set) var state: State = .idle

    private let provider: any AppleCalendarProviding

    init(provider: any AppleCalendarProviding = AppleCalendarProvider.shared) {
        self.provider = provider
    }

    func loadIfAuthorized(around date: Date = Date()) async {
        switch await provider.accessStatus() {
        case .notDetermined:
            state = .needsPermission
        case .denied:
            state = .denied
        case .fullAccess:
            await loadEvents(around: date)
        }
    }

    func requestAccessAndLoad(around date: Date = Date()) async {
        state = .loading
        do {
            switch try await provider.requestFullAccess() {
            case .fullAccess:
                await loadEvents(around: date)
            case .notDetermined:
                state = .needsPermission
            case .denied:
                state = .denied
            }
        } catch {
            state = .failed
        }
    }

    func reload(around date: Date = Date()) async {
        guard await provider.accessStatus() == .fullAccess else {
            await loadIfAuthorized(around: date)
            return
        }
        await loadEvents(around: date)
    }

    private func loadEvents(around date: Date) async {
        switch state {
        case .ready:
            // Keep authorized candidates visible during a foreground refresh.
            break
        default:
            state = .loading
        }
        do {
            state = .ready(try await provider.nearbyEvents(around: date))
        } catch {
            state = .failed
        }
    }
}
