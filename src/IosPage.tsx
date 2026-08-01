import { useEffect } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { Footer } from "./Footer";
import { WaitlistForm } from "./WaitlistForm";
import { WAITLIST_COPY } from "./waitlistCopy";

// inhavens.com/#/ios.
//
// Haven for iPhone is the primary client -- mvp-design.md owns the product
// vision -- and it is still in development, so this page's job is to
// introduce it honestly and carry the waitlist signup that used to sit at the
// site's root. WAITLIST_COPY (eyebrow, headline, tagline) is the pitch that
// page always carried; it lives here now because this is where joining
// happens. WaitlistForm is the ask itself, extracted so this page reuses it
// rather than duplicating the join logic.
//
// Public and unauthenticated, like the sky download page: reachable at
// "#/ios" (and its older alias "#/join") for anyone with the link.
const COMING = [
  {
    title: "One profile",
    body: "A single Haven profile you share instead of trading numbers back and forth.",
  },
  {
    title: "Connect in one tap",
    body: "Meet someone, tap to connect, and you are in each other's directory -- no typing a number by hand.",
  },
  {
    title: "Find anyone by any detail",
    body: "Search your own network the way you actually remember people -- by what they do, where you met, or a name half-remembered.",
  },
] as const;

export function IosPage() {
  useEffect(() => {
    document.title = "Haven for iPhone - Haven";
  }, []);

  return (
    <div className="card-page">
      <DriftSky className="card-sky" />
      <TopNav />
      <main className="ios-page">
        <div className="ios-hero">
          <span className="ios-eyebrow">{WAITLIST_COPY.eyebrow}</span>
          <h1 className="ios-title">{WAITLIST_COPY.headline}</h1>
          <p className="ios-tagline">{WAITLIST_COPY.sub}</p>
          <p className="ios-status">
            Haven for iPhone is in development. Join the list and we will
            email you when it is ready.
          </p>
        </div>

        <section className="ios-join" aria-label="Join the waitlist">
          <WaitlistForm />
        </section>

        <section className="ios-about" aria-label="What's coming to Haven for iPhone">
          <h2>What's coming</h2>
          <ul>
            {COMING.map((item) => (
              <li key={item.title}>
                <strong>{item.title}.</strong> {item.body}
              </li>
            ))}
          </ul>
        </section>
      </main>
      <Footer />
    </div>
  );
}
