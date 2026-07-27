import { useEffect } from "react";
import type { LegalDoc } from "./lib";

// The date the wording below last changed. Bump it whenever the text does:
// a policy whose "last updated" line is stale is worse than none, because it
// asserts something about data handling that may no longer be true.
const LAST_UPDATED = "27 July 2026";

const CONTACT = "hello@inhavens.com";

const TITLES: Record<LegalDoc, string> = {
  privacy: "Privacy Policy",
  terms: "Terms of Service",
};

// inhavens.com/privacy and inhavens.com/terms.
//
// These exist because the App Store will not take a submission without a
// privacy policy url, but the reason to write them properly is that Haven asks
// people to store notes about other people. Someone deciding whether to do that
// deserves a straight answer about where it goes, in words they do not need a
// lawyer to read.
//
// Public and signed out, like the card page: App Review opens the url from App
// Store Connect with no session, and anything but the document reads as broken.
export function LegalPage({ doc }: { doc: LegalDoc }) {
  useEffect(() => {
    document.title = `${TITLES[doc]} - Haven`;
  }, [doc]);

  return (
    <div className="card-page">
      <main className="legal-page">
        <a className="legal-back" href="/">
          Haven
        </a>
        <h1 className="legal-title">{TITLES[doc]}</h1>
        <p className="legal-updated">Last updated {LAST_UPDATED}</p>
        {doc === "privacy" ? <PrivacyBody /> : <TermsBody />}
        <p className="legal-footer">
          {doc === "privacy" ? (
            <a href="/terms">Terms of Service</a>
          ) : (
            <a href="/privacy">Privacy Policy</a>
          )}
          <span aria-hidden="true"> / </span>
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a>
        </p>
      </main>
    </div>
  );
}

function PrivacyBody() {
  return (
    <>
      <p className="legal-lede">
        Haven is a private notebook for the people you meet. Almost everything
        in it is yours alone, and the one thing that is public is public because
        you chose to hand it to someone. This page says exactly what we hold,
        who else touches it, and how to get rid of all of it.
      </p>

      <h2>What we hold</h2>
      <p>
        <strong>Your account.</strong> When you sign in, our authentication
        provider gives us a user id and an email address. If you use Sign in
        with Apple and choose to hide your address, the relay address is the
        only one we ever see. We never receive your Apple password.
      </p>
      <p>
        <strong>Your card.</strong> Your name, your Haven handle, and whatever
        else you fill in: a photo, a city, a company, a role, and up to four
        contact handles across Instagram, X, LinkedIn, and phone. Every field
        except the handle is optional, and an empty one stays empty.
      </p>
      <p>
        <strong>People you save.</strong> Their name, and anything you add about
        them: company, role, city, links, social handles, a photo, a screenshot
        you captured them from, and where you met.
      </p>
      <p>
        <strong>What you write about them.</strong> Your notes, kept line by
        line so that search can reach a single detail rather than a whole
        paragraph.
      </p>
      <p>
        <strong>The waitlist.</strong> If you joined from the website, the name
        and email address you gave us there.
      </p>
      <p>
        <strong>Two things that never leave your phone.</strong> Which
        onboarding questions you have answered, and whether you have dismissed
        the widget suggestion. Both are local settings, not records about you.
      </p>

      <h2>What we do not do</h2>
      <p>
        No advertising. No analytics SDKs. No tracking you across other
        companies' apps or websites. We do not sell your data, and we do not
        share it with anyone for their own purposes.
      </p>

      <h2>Who else touches it</h2>
      <p>
        We do not run our own servers, so a small number of providers process
        data on our behalf, under contract, only to make Haven work:
      </p>
      <ul>
        <li>
          <strong>Clerk</strong> handles sign-in and holds your account
          identity.
        </li>
        <li>
          <strong>Convex</strong> is the database and file storage where your
          card, your people, your notes, and your photos live.
        </li>
        <li>
          <strong>An AI provider</strong> receives the text of your notes and of
          the profiles you save, so that Haven can make them searchable by
          meaning and answer questions you ask about your own network. We only
          use providers whose terms keep that text out of model training.
        </li>
        <li>
          <strong>Vercel</strong> serves the website.
        </li>
      </ul>

      <h2>What is public, and what is not</h2>
      <p>
        Your card at inhavens.com/your-handle is public to anyone who has the
        link. That is the point of it: it is what a stranger sees after scanning
        your beacon, and it shows only the fields you filled in.
      </p>
      <p>
        Everything else is private to you. The people you save cannot see that
        you saved them, and nobody but you can read your notes.
      </p>

      <h2>Notes about other people</h2>
      <p>
        Haven is built to hold what you remember about people you have met, and
        those people did not sign up for it. We treat that seriously and we ask
        you to as well: write what you would be comfortable having read back to
        you, and keep it lawful where you live. Your directory is yours, and you
        are the one responsible for what goes in it. If someone asks you to
        remove what you have written about them, please do.
      </p>
      <p>
        If you believe Haven holds something about you that a user should not
        have written, write to us at {CONTACT} and we will look into it.
      </p>

      <h2>How long we keep it</h2>
      <p>
        For as long as your account exists. Delete your account and it goes,
        promptly and for good.
      </p>

      <h2>Deleting everything</h2>
      <p>
        In the app, open My Card and choose "Delete your account". That removes
        your card, every person you have saved, every note attached to them,
        your photos and screenshots, and the sign-in itself. It cannot be
        undone. Routine backups taken before you deleted expire on their own
        schedule, and nothing is kept beyond them.
      </p>
      <p>
        One thing survives, and it is not yours: if another Haven user saved you
        into their own directory and wrote their own notes about you, those are
        their records rather than your account, and deleting yours does not
        reach into theirs.
      </p>

      <h2>Your rights</h2>
      <p>
        Depending on where you live you may have the right to see the data we
        hold about you, correct it, export it, or have it deleted. The app
        already gives you all four for your own account. For anything the app
        does not cover, write to {CONTACT} and we will answer.
      </p>

      <h2>Children</h2>
      <p>
        Haven is not for people under 13, and we do not knowingly hold data
        about them. If you believe a child has an account, tell us and we will
        remove it.
      </p>

      <h2>Where the data sits</h2>
      <p>
        Our providers operate in the United States, so if you use Haven from
        elsewhere your data is transferred and processed there.
      </p>

      <h2>Changes</h2>
      <p>
        If we change how any of this works, we will change this page and move
        the date at the top. For a change that materially affects you, we will
        tell you in the app rather than leave you to notice.
      </p>

      <h2>Contact</h2>
      <p>Questions, requests, or complaints: {CONTACT}.</p>
    </>
  );
}

function TermsBody() {
  return (
    <>
      <p className="legal-lede">
        Plain terms for using Haven. Using the app means you accept them.
      </p>

      <h2>What Haven is</h2>
      <p>
        A private place to keep your card and the people you meet. It is an
        early product: things will change, and occasionally something will
        break.
      </p>

      <h2>Your account</h2>
      <p>
        One account per person, and you need to be at least 13. Keep your
        sign-in to yourself, because whoever holds it holds everything in your
        directory.
      </p>

      <h2>What you write stays yours</h2>
      <p>
        Your card, your people, and your notes belong to you. You give us only
        the permission we need to run the service: to store what you write, show
        it back to you, and publish the card you chose to make public. We do not
        claim anything else, and we do not use your content for anything but
        running Haven for you.
      </p>

      <h2>What you put in it</h2>
      <p>
        Haven holds notes about other people, so this part matters. Write what
        is lawful where you live, and do not use Haven to harass anyone, to
        collect data about people you have no business collecting, or to
        impersonate someone. Do not scrape the service, break into parts of it
        that are not yours, or resell it.
      </p>

      <h2>Your public card</h2>
      <p>
        Making a card public means it can be seen by anyone with the link, and
        can be indexed by search engines. Do not put anything on it you would
        not hand to a stranger, because that is exactly what it is for.
      </p>

      <h2>What we can do</h2>
      <p>
        We can suspend or close an account that is being used to harm someone or
        to abuse the service. We would rather write to you first, and normally
        will.
      </p>

      <h2>No promises we cannot keep</h2>
      <p>
        Haven is provided as it is. We work hard to keep your data safe and
        available, but we cannot guarantee the service will be uninterrupted or
        error-free, and to the extent the law allows we are not liable for
        losses arising from your use of it. Keep your own copy of anything you
        cannot afford to lose.
      </p>

      <h2>Ending it</h2>
      <p>
        Delete your account from My Card whenever you like, and everything goes
        with it. See the{" "}
        <a href="/privacy">Privacy Policy</a> for exactly what that removes.
      </p>

      <h2>Changes</h2>
      <p>
        We will update this page when the terms change and move the date at the
        top.
      </p>

      <h2>Contact</h2>
      <p>{CONTACT}.</p>
    </>
  );
}
