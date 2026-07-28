import SwiftUI

/// Fetches the photo a card shows.
///
/// Its own type rather than an `AsyncImage` inside `HavenCard`, because the
/// card is a dumb view: it is handed everything it draws, which is what lets a
/// preview render one without a network. Both screens that show a card load the
/// photo the same way and pass it in.
enum CardPhoto {
    /// The photo, or nil for a card that has none, a url that will not load, or
    /// bytes that are not an image. A card without a photo is an ordinary card,
    /// so none of those is an error worth surfacing.
    static func load(_ url: URL?) async -> Image? {
        guard let url else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        // Convex hands back a signed url that has expired or been revoked as an
        // ordinary 403, not as a transport error, and UIImage would decode the
        // error page's bytes into nothing anyway.
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }
        return Image(uiImage: image)
    }
}

/// Keeps a card's photo in step with the card.
///
/// A modifier rather than two copies of the same `@State` and `.task`: My Card
/// and the reveal both need it, and the part that is easy to get wrong --
/// re-fetching when the url changes and clearing when it goes away -- should
/// exist once.
private struct CardPhotoLoader: ViewModifier {
    let url: URL?
    @Binding var photo: Image?

    func body(content: Content) -> some View {
        content.task(id: url) {
            let loaded = await CardPhoto.load(url)
            // A cancelled fetch returns nil like any other failure, and writing
            // that would clear a photo the replacement task has already loaded.
            guard !Task.isCancelled else { return }
            photo = loaded
        }
    }
}

extension View {
    /// Loads `url` into `photo`, refetching whenever the url changes.
    func cardPhoto(_ url: URL?, into photo: Binding<Image?>) -> some View {
        modifier(CardPhotoLoader(url: url, photo: photo))
    }
}
