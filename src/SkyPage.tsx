import { useEffect } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { Footer } from "./Footer";

// inhavens.com/#/sky.
//
// Your Sky is a separate Mac app, not a screen inside the web product: it
// reads a person's own iMessage history and Contacts locally and draws the
// 3D map of everyone they know. This page's whole job is to sell that flow
// honestly -- download, authorize, map -- and to say exactly what does and
// does not leave the machine, because the thing this app touches (who you
// talk to, how often) is more sensitive than anything else Haven asks for.
//
// Public and unauthenticated, like the waitlist: reachable at "#/sky" for
// anyone with the link, signed in or out is irrelevant to a Mac download.
const DOWNLOAD_HREF = "/downloads/YourSky.zip";

const STEPS = [
  {
    title: "Download",
    body: "Get Your Sky for Mac and drag it into Applications, like any other app.",
  },
  {
    title: "Authorize access",
    body: "Your Sky asks macOS for Full Disk Access, so it can read your Messages database and Contacts on this Mac. It walks you through the one setting to flip.",
  },
  {
    title: "Map relationships",
    body: "Click “Map relationships” and watch your sky take shape: everyone you have messaged, positioned by how close you actually are.",
  },
] as const;

// Every sentence here is a legal and trust boundary, not just marketing copy
// -- see docs/2026-07-30-imessage-connection-graph-research.md. Two rules
// this list must keep: never claim something "never leaves your device" in
// an unscoped way (a future sync feature would make that a lie retroactively),
// and always name that the map is built from metadata, not message text.
const PRIVACY_POINTS = [
  "Analysis happens on your Mac. Your messages are never uploaded anywhere.",
  "The map is built from metadata -- who you messaged, when, and how often -- never the contents of a message.",
  "If you have Ollama installed, an optional local AI model can suggest names for numbers you have not saved. That runs on your Mac too, and it is off unless you turn it on.",
] as const;

export function SkyPage() {
  useEffect(() => {
    document.title = "Your Sky - Haven";
  }, []);

  return (
    <div className="card-page">
      <DriftSky className="card-sky" />
      <TopNav links={false} />
      <main className="sky-page">
        <div className="sky-hero">
          <span className="sky-eyebrow">Your Sky, for Mac</span>
          <h1 className="sky-title">Every person you know, in one map.</h1>
          <p className="sky-tagline">
            Your Sky reads your own iMessage history and Contacts on your Mac
            and draws the people you actually talk to as a 3D map you can
            explore.
          </p>
          <div className="landing-hero-ctas">
            <a className="sky-download" href={DOWNLOAD_HREF}>
              Download for Mac
            </a>
            <a className="landing-cta-secondary" href="#/ios">
              Join the iPhone waitlist
            </a>
          </div>
          <p className="sky-install-note">
            This build is not notarized yet -- macOS will warn on first open.
            Go to <strong>System Settings &gt; Privacy &amp; Security</strong>{" "}
            and choose <strong>Open Anyway</strong>. Requires macOS 14 or
            later, and Full Disk Access so Your Sky can read your Messages
            database (it walks you through granting it).
          </p>
        </div>

        <section className="sky-steps" aria-label="How it works">
          <h2>How it works</h2>
          <ol className="sky-step-list">
            {STEPS.map((step, index) => (
              <li className="sky-step" key={step.title}>
                <span className="sky-step-index" aria-hidden="true">
                  {index + 1}
                </span>
                <div>
                  <h3 className="sky-step-title">
                    {index === 0 ? (
                      <a href={DOWNLOAD_HREF}>{step.title}</a>
                    ) : (
                      step.title
                    )}
                  </h3>
                  <p className="sky-step-body">{step.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section className="sky-privacy" aria-label="Privacy">
          <h2>What stays on your Mac</h2>
          <ul>
            {PRIVACY_POINTS.map((point) => (
              <li key={point}>{point}</li>
            ))}
          </ul>
        </section>

        <a className="sky-download sky-download-repeat" href={DOWNLOAD_HREF}>
          Download for Mac
        </a>
      </main>
      <Footer />
    </div>
  );
}
