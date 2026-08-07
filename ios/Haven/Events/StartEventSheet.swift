import SwiftUI

struct StartEventSheet: View {
    let start: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var didFail = false
    @State private var starts = 0

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
                        Text("Event name")
                            .havenGroupLabel()
                        HavenField(
                            label: "Event name",
                            placeholder: "Founders dinner",
                            text: $title,
                            capitalization: .sentences,
                            submitLabel: .done,
                            autofocus: true,
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
    }

    private func begin() {
        guard start(title) else {
            didFail = true
            return
        }
        starts += 1
        dismiss()
    }
}

#Preview("Start event") {
    StartEventSheet(start: { _ in true })
}

#Preview("Start event, accessibility XXXL") {
    StartEventSheet(start: { _ in true })
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Start event, Reduce Motion") {
    StartEventSheet(start: { _ in true })
        .havenReduceMotion()
}
