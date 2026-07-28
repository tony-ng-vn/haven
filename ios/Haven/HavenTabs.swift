import SwiftUI

/// The app once onboarding is over: People and Search, with the card reachable
/// from the People screen's toolbar.
///
/// Two tabs rather than one screen whose search field expands, per the build
/// plan's open question 3. The tab bar is also where Phase 2 grows.
struct HavenTabs: View {
    /// The Clerk user id. The directory keys its dismissed suggestions by it,
    /// so a second account on the same phone starts clean.
    let userId: String
    /// Opens straight onto My Card. The reveal's "Add another way to reach me"
    /// arrives here, and landing on People first would make that ghost button
    /// feel like it had not worked.
    var opensCard = false

    @State private var tab: Tab = .people
    @State private var peopleRoute: [Destination] = []
    /// Which side of the card is up.
    ///
    /// Here rather than inside My Card because the Lock Screen widget asks for
    /// the code as an event, not as a destination: it can arrive when the card
    /// is already open and showing its front, and it can arrive twice.
    @State private var showingCode = false
    /// Which legal page the menu asked for, if any.
    @State private var legalDocument: LegalDocument?
    /// Whether the connect scanner is open.
    @State private var scanning = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $peopleRoute) {
                // People's search field is not a field: it hands the whole
                // interaction to the tab that owns searching, rather than
                // imitating it and then having to keep the two in step.
                DirectoryScreen(
                    userId: userId,
                    openSearch: { tab = .search },
                    openPerson: { peopleRoute.append(.person(id: $0)) }
                )
                    .toolbar { directoryToolbar }
                    .navigationDestination(for: Destination.self) { destination in
                        switch destination {
                        case .card: MyCardScreen(showingCode: $showingCode)
                        case .person(let id): PersonScreen(personId: id)
                        }
                    }
            }
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(Tab.people)

            NavigationStack {
                SearchScreen()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)
        }
        // Selection is Star everywhere else in Haven, and the system default
        // accent is the one colour the palette does not contain.
        .tint(HavenColor.star)
        // On the TabView rather than inside the People stack, so the page
        // covers the tab bar the way a sheet from anywhere else in Haven does.
        .legalSheet($legalDocument)
        // On the TabView for the same reason the legal sheet is: the scanner
        // covers the tab bar, which is what a sheet in Haven does.
        .sheet(isPresented: $scanning) {
            ConnectScreen { personId in
                tab = .people
                peopleRoute.append(.person(id: personId))
            }
        }
        .onAppear {
            if opensCard { openCard(showingCode: false) }
        }
        // The Lock Screen widget's tap arrives here, and lands on the card
        // already turned to its code, because the code is the whole of what
        // that widget offers. The card hangs off the People tab's stack, so the
        // tab has to come along or the push lands on a stack nobody is looking
        // at.
        .onOpenURL { url in
            guard HavenDeepLink(url: url) == .beacon else { return }
            tab = .people
            openCard(showingCode: true)
        }
    }

    /// Every way into My Card says which side of the card it wants, because
    /// none of them can assume which side the last visit left it on.
    private func openCard(showingCode: Bool) {
        self.showingCode = showingCode
        if peopleRoute != [.card] { peopleRoute = [.card] }
    }

    private enum Tab {
        case people
        case search
    }

    /// Where the People tab can go. A value rather than a view, so the reveal
    /// and the widget can open it without holding the view that shows it.
    private enum Destination: Hashable {
        case card
        case person(id: String)
    }

    /// One door to the card, not two.
    ///
    /// There used to be a second button here for the beacon. The code is the
    /// back of the card now, so a separate way in would be a second route to
    /// the same object -- and the one that skipped the card would be the one
    /// people learned.
    ///
    /// A button rather than a `NavigationLink`, because opening the card also
    /// has to say which side is up: a link can only carry a destination.
    @ToolbarContentBuilder
    private var directoryToolbar: some ToolbarContent {
        // The legal pages, somewhere a person can find them without owning a
        // card. My Card carries them too, but that is a screen about you, and
        // someone looking for the privacy policy is not looking for themselves.
        //
        // Leading, so the card keeps the trailing corner it has always had:
        // moving the one control people already reach for to make room for the
        // one they will want twice would be the wrong trade.
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(LegalDocument.allCases) { document in
                    Button(document.title) { legalDocument = document }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }

        // Scanning is the other half of the card: one corner shows your code,
        // the other reads somebody else's. Beside the card rather than in the
        // menu, because it is a thing people do standing up in front of
        // somebody, and a menu is two taps.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                scanning = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            .accessibilityLabel("Scan someone's card")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openCard(showingCode: false)
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Your card")
        }
    }
}

#Preview("Tabs") {
    HavenTabs(userId: "preview_user")
}

#Preview("Tabs, accessibility XXXL") {
    HavenTabs(userId: "preview_user")
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tabs, Reduce Motion") {
    HavenTabs(userId: "preview_user")
        .havenReduceMotion()
}
