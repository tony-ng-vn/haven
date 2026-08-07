import SwiftUI
import UIKit

struct StartEventSheet: View {
    let start: (String, EventSourceReference?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var calendar: AppleCalendarModel
    @State private var title = ""
    @State private var selectedEvent: CalendarEventCandidate?
    @State private var didFail = false
    @State private var starts = 0

    init(
        start: @escaping (String, EventSourceReference?) -> Bool,
        calendarProvider: any AppleCalendarProviding = AppleCalendarProvider.shared
    ) {
        self.start = start
        _calendar = StateObject(wrappedValue: AppleCalendarModel(provider: calendarProvider))
    }

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { EmptyView() },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start an event")
                            .havenQuestion()
                        Text("Everyone you save until you end it will be remembered with this event.")
                            .havenHint()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apple Calendar")
                            .havenGroupLabel()
                        calendarContent
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or type an event")
                            .havenGroupLabel()
                        HavenField(
                            label: "Event name",
                            placeholder: "Founders dinner",
                            text: $title,
                            capitalization: .sentences,
                            submitLabel: .done,
                            autofocus: false,
                            onSubmit: begin
                        )
                        if didFail {
                            Text("Haven could not start that event. Try again.")
                                .havenSecondary(HavenColor.ember)
                        }
                    }
                    .padding(.top, 28)

                    VStack(spacing: 8) {
                        PrimaryButton(title: "Start event", action: begin)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        GhostButton(title: "Cancel") { dismiss() }
                    }
                    .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            actions: { EmptyView() }
        )
        .havenDismissable()
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .light), trigger: starts)
        .task {
            await calendar.loadIfAuthorized()
        }
        .onChange(of: title) { _, newTitle in
            guard let selectedEvent, selectedEvent.title != newTitle else { return }
            self.selectedEvent = nil
        }
        .onChange(of: calendar.state) { _, state in
            reconcileSelection(with: state)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await calendar.loadIfAuthorized() }
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch calendar.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(HavenColor.star)
                Text("Looking for nearby events...")
                    .havenSecondary()
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)

        case .needsPermission:
            HavenRow(
                title: "Choose from Apple Calendar",
                detail: "Haven saves only the event you choose.",
                accessibilityText: "Choose from Apple Calendar. Haven saves only the event you choose.",
                action: requestCalendarAccess,
                leading: {
                    Image(systemName: "calendar")
                        .foregroundStyle(HavenColor.star)
                        .accessibilityHidden(true)
                },
                trailing: { RowMark.chevron }
            )

        case .ready(let events):
            if events.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No nearby events")
                        .havenBody()
                    Text("You can still type an event below.")
                        .havenSecondary()
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(events) { event in
                    CalendarCandidateRow(
                        event: event,
                        isSelected: selectedEvent?.id == event.id,
                        onSelect: { select(event) }
                    )
                }
            }

        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar access is off")
                    .havenBody()
                Text("Turn it on in Settings, or type an event below.")
                    .havenSecondary()
                Button("Open Settings", action: openSettings)
                    .font(HavenFont.buttonLabel)
                    .foregroundStyle(HavenColor.star)
                    .frame(minHeight: 44, alignment: .leading)
            }

        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Haven could not read your nearby events.")
                    .havenSecondary(HavenColor.ember)
                Button("Try again", action: reloadCalendar)
                    .font(HavenFont.buttonLabel)
                    .foregroundStyle(HavenColor.star)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func requestCalendarAccess() {
        Task { await calendar.requestAccessAndLoad() }
    }

    private func reloadCalendar() {
        Task { await calendar.reload() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func select(_ event: CalendarEventCandidate) {
        didFail = false
        selectedEvent = event
        title = event.title
    }

    private func reconcileSelection(with state: AppleCalendarModel.State) {
        guard let selectedEvent else { return }
        guard case .ready(let events) = state,
              let refreshed = events.first(where: { $0.id == selectedEvent.id }) else {
            if title == selectedEvent.title { title = "" }
            self.selectedEvent = nil
            return
        }
        self.selectedEvent = refreshed
        title = refreshed.title
    }

    private func begin() {
        guard start(title, selectedEvent?.source) else {
            didFail = true
            return
        }
        starts += 1
        dismiss()
    }
}

private struct CalendarCandidateRow: View {
    let event: CalendarEventCandidate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? HavenColor.star : HavenColor.faint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .havenBody()
                    Text(detail)
                        .havenSecondary()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? HavenColor.fill : HavenColor.rowHighlight,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(detail)")
        .accessibilityHint("Uses this name for Event Mode")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var detail: String {
        let time: String
        if event.isAllDay {
            time = "All day"
        } else {
            let start = event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            let end = event.end.formatted(.dateTime.hour().minute())
            time = "\(start) - \(end)"
        }
        return time
    }
}

#Preview("Start event") {
    StartEventSheet(start: { _, _ in true })
}

#Preview("Start event, accessibility XXXL") {
    StartEventSheet(start: { _, _ in true })
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Start event, Reduce Motion") {
    StartEventSheet(start: { _, _ in true })
        .havenReduceMotion()
}
