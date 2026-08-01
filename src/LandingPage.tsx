import { useEffect } from "react";
import { DriftSky } from "./DriftSky";

// inhavens.com/, signed out.
//
// The Haven landing: what Haven is, in a sentence, then the two products each
// with their own path onward. This is the site's front door now, replacing
// the waitlist that used to sit here directly -- so anyone who held a link to
// the root expecting to join still finds that one click away, on the iPhone
// card.
//
// The iPhone card is first for that reason: it keeps the waitlist path above
// the fold on a phone, where the two cards stack and the second one would
// otherwise sit past the first scroll.
export function LandingPage() {
  useEffect(() => {
    document.title = "Haven - A memory layer for the people you meet";
  }, []);

  return (
    <div className="card-page">
      <DriftSky className="card-sky" />
      <main className="landing-page">
        <div className="landing-hero">
          <span className="landing-brand">Haven</span>
          <h1 className="landing-tagline">
            Haven keeps a memory of the people you meet, so you can find them
            again when you forget their name.
          </h1>
        </div>

        <div className="landing-products">
          <article className="landing-card">
            <span className="landing-card-kicker">Haven, for iPhone</span>
            <h2 className="landing-card-title">Never lose someone you meet</h2>
            <p className="landing-card-body">
              Connect with someone in one tap, and find them again later by
              any detail you remember.
            </p>
            <a className="landing-card-cta" href="#/ios">
              Join the waitlist
            </a>
          </article>

          <article className="landing-card">
            <span className="landing-card-kicker">Your Sky, for Mac</span>
            <h2 className="landing-card-title">Map who you already talk to</h2>
            <p className="landing-card-body">
              Reads your own iMessage history and Contacts, locally on your
              Mac, and draws everyone you talk to as a map.
            </p>
            <a className="landing-card-cta" href="#/sky">
              Try Your Sky for Mac
            </a>
          </article>
        </div>
      </main>
    </div>
  );
}
