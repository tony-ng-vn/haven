import ConvexMobile
import SwiftUI

/// Every way someone can be reached, with one of them marked primary.
///
/// Onboarding collects exactly one. This is where the rest are added, and where
/// the choice of which one leads is made -- the card, the public page and the
/// directory all read `primaryPlatform`, so it is a real decision rather than
/// an ordering preference.
struct HandlesEditor: View {
    let handles: [MyCard.Handle]
    let primary: MyCard.Platform?
    let save: ([MyCard.Handle], MyCard.Platform?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var adding: MyCard.Platform?
    @State private var working = false

    /// The platforms with no handle yet. One per platform, the same rule the
    /// server enforces, because `primaryPlatform` points at a platform rather
    /// than at a row and two would make that pointer ambiguous.
    private var available: [MyCard.Platform] {
        let taken = Set(handles.map(\.platform))
        return [.x, .instagram, .linkedin, .phone].filter { !taken.contains($0) }
    }

    var body: some View {
        HavenScreen(
            question: "Ways to reach you",
            hint: "The one marked Primary is what your card leads with.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(handles, id: \.platform) { handle in
                    HavenRow(
                        title: handle.display,
                        detail: handle.platform == primary ? "Primary" : nil,
                        accessibilityText: spoken(handle)
                    ) {
                        makePrimary(handle)
                    } leading: {
                        EmptyView()
                    } trailing: {
                        Button {
                            remove(handle)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(HavenColor.faint)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Remove \(handle.display)")
                    }
                }

                if !available.isEmpty {
                    Text("Add another")
                        .havenGroupLabel()
                        .padding(.top, 20)
                        .padding(.bottom, 6)
                    ForEach(available, id: \.self) { platform in
                        HavenRow(title: platform.label) {
                            adding = platform
                        } leading: {
                            EmptyView()
                        } trailing: {
                            RowAccessory(text: "Add")
                        }
                    }
                }
            }
        } actions: {
            GhostButton(title: "Done") { dismiss() }
        }
        .sheet(item: $adding) { platform in
            HandleValueEditor(platform: platform) { value in
                await add(platform, value: value)
            }
        }
        .disabled(working)
    }

    private func spoken(_ handle: MyCard.Handle) -> String {
        let role = handle.platform == primary ? "primary" : "make primary"
        return "\(handle.platform.label), \(handle.display), \(role)"
    }

    private func makePrimary(_ handle: MyCard.Handle) {
        guard handle.platform != primary else { return }
        commit(handles, primary: handle.platform)
    }

    private func remove(_ handle: MyCard.Handle) {
        let remaining = handles.filter { $0.platform != handle.platform }
        // Removing the primary hands the role to whatever is left rather than
        // leaving a card that names a platform it no longer has.
        let stillPrimary = primary == handle.platform ? remaining.first?.platform : primary
        commit(remaining, primary: stillPrimary)
    }

    private func add(_ platform: MyCard.Platform, value: String) async {
        let entry = MyCard.Handle(platform: platform, value: value, verified: false)
        // The first one added is the one the card leads with, because a card
        // with a way to reach someone and no primary would show nothing.
        await save(handles + [entry], primary ?? platform)
    }

    private func commit(_ next: [MyCard.Handle], primary next2: MyCard.Platform?) {
        working = true
        Task {
            await save(next, next2)
            working = false
        }
    }
}

/// Typing one handle. No authorization here: connecting an account is
/// onboarding's job, and a value typed by hand was by definition not proven by
/// the platform, so it is never stored verified.
private struct HandleValueEditor: View {
    let platform: MyCard.Platform
    let save: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    private var parsed: String? {
        switch platform {
        case .instagram: return ContactValue.instagramHandle(from: text)
        case .x: return ContactValue.xHandle(from: text)
        case .linkedin: return ContactValue.linkedInHandle(from: text)
        case .phone: return ContactValue.phoneNumber(from: text)
        }
    }

    var body: some View {
        HavenScreen(
            question: platform.label,
            hint: platform == .phone
                ? "Only you see this. It is never on your public page."
                : "Paste a link or type the handle."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HavenField(
                    label: platform.label,
                    placeholder: platform == .phone ? "Your number" : platform.addressPrefix + "handle",
                    text: $text,
                    contentType: platform == .phone ? .telephoneNumber : nil,
                    keyboard: platform == .phone ? .phonePad : .URL,
                    capitalization: .never,
                    submitLabel: .done,
                    autofocus: true,
                    onSubmit: commit
                )
                // What will actually be stored, as it is typed. A pasted URL
                // reducing to a handle in front of someone is what stops the
                // save being a surprise.
                if let parsed {
                    Text(MyCard.Handle(platform: platform, value: parsed, verified: false).display)
                        .havenSecondary()
                }
            }
        } actions: {
            PrimaryButton(title: "Save", isLoading: working, action: commit)
                .disabled(parsed == nil)
        }
    }

    private func commit() {
        guard let parsed, !working else { return }
        working = true
        Task {
            await save(parsed)
            dismiss()
        }
    }
}

extension MyCard.Handle {
    var convexArgument: [String: ConvexEncodable?] {
        ["platform": platform.rawValue, "value": value, "verified": verified]
    }
}
