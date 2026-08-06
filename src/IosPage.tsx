import { useEffect } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { Footer } from "./Footer";
import { WaitlistForm } from "./WaitlistForm";
import { WAITLIST_COPY } from "./waitlistCopy";

// inhavens.com/, and inhavens.com/#/ios.
//
// Haven for iPhone is the primary client -- mvp-design.md owns the product
// vision -- and it is still in development, so this page's job is to
// introduce it honestly and carry the waitlist signup. It is also the bare
// root's front door again (see resolveView in lib.ts): the owner tried a
// landing hero there instead for a while, then asked for the waitlist back,
// so the two landing designs live on at their own urls (/landing,
// #/landing2) rather than being deleted, and this is what a stranger with no
// link at all actually meets. WAITLIST_COPY (eyebrow, headline, tagline) is
// the pitch this page carries; WaitlistForm is the ask itself, extracted so
// this page reuses it rather than duplicating the join logic.
//
// Public and unauthenticated, like the sky download page: reachable at the
// root, "#/ios", and the older alias "#/join" alike, for anyone with any of
// those links.
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
