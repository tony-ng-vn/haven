import { useEffect } from "react";

// The date the answers below were last checked against the product. Bump it
// whenever one changes: a support page that describes a flow the app no longer
// has costs more trust than no page at all.
const LAST_CHECKED = "29 July 2026";

const CONTACT = "hello@inhavens.com";

// inhavens.com/support.
//
// The App Store asks for a Support URL, and the honest destination until now
// was the landing page -- which reads to a reviewer as "there is no support".
// But the reason to write it properly is that the person most likely to open
// it is someone locked out of their account, or someone who wants their data
// gone. Both deserve a straight answer on the first screen rather than a
// contact form.
//
// Public and signed out, like the card and legal pages: a page that requires
// the account you are locked out of is not support.
//
// It reuses the .legal-page styles rather than growing a second copy of the
// same document shell. The class name says legal; what it actually styles is
// "a plain page of prose on the night background".
export function SupportPage() {
  useEffect(() => {
    document.title = "Support - Haven";
  }, []);

  return (
    <div className="card-page">
      <main className="legal-page">
        <a className="legal-back" href="/">
          Haven
        </a>
        <h1 className="legal-title">Support</h1>
        <p className="legal-updated">Answers last checked {LAST_CHECKED}</p>

        <p className="legal-lede">
          Haven is a private notebook for the people you meet. If something is
          broken, or you want your data gone, write to{" "}
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a> and a person will answer.
        </p>

        <h2>I cannot sign in</h2>
        <p>
          Most people sign in with Apple, and there is no separate Haven
          password behind that. If <strong>Continue with Apple</strong> does
          nothing, check that you are signed in to iCloud on the device under{" "}
          <strong>Settings</strong>. If you signed up another way, use{" "}
          <strong>Other ways to sign in</strong> on the welcome screen, which is
          also where a sign-in code can be sent to you again.
        </p>
        <p>
          If it keeps failing, mail us the address you signed up with and
          roughly when you last got in. If you used Apple's{" "}
          <strong>Hide My Email</strong>, the address we hold is a relay one --
          writing from it still reaches us, and it is the fastest way for us to
          find your account.
        </p>

        <h2>How do I delete my account?</h2>
        <p>
          In the app: open <strong>My Card</strong>, scroll to the bottom, and
          tap <strong>Delete your account</strong>. It asks once to be sure, and
          then it is done -- there is no waiting period and no separate request
          to us.
        </p>
        <p>
          That removes your card, your handle, everyone in your directory, your
          notes, your captures and their images, and your account itself. Your
          handle goes back into circulation and your card page stops resolving.
          People who had connected with you keep the copy of your card they
          already saved, frozen as it was; nothing you write after that reaches
          them. See the <a href="/privacy">Privacy Policy</a> for exactly what
          that removes.
        </p>
        <p>
          If you cannot get into the app to do it, mail{" "}
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a> from the address on the
          account and we will do it for you.
        </p>

        <h2>Can other people see my notes?</h2>
        <p>
          No. Notes you write about someone are yours alone. They are never
          shown to the person they are about, never sent to them, and are not
          part of what a connection shares. The only thing anyone else sees is
          your card -- the fields you filled in yourself.
        </p>

        <h2>Someone scanned my code and it opened Safari</h2>
        <p>
          That is the fallback, and it still works: the web page shows the same
          card. The code opens the app instead once both people have Haven
          installed from the App Store. Nothing is lost either way.
        </p>

        <h2>I want a different handle</h2>
        <p>
          Handles are unique, and yours is minted for you when you first sign
          in. If you want a different one, write to us with the handle you have
          in mind and we will tell you whether it is free.
        </p>

        <h2>Remove someone from my directory</h2>
        <p>
          Open them from your directory, tap <strong>Edit</strong>, then{" "}
          <strong>Delete this person</strong>. If you connected with them in
          Haven, <strong>Disconnect</strong> in the same place keeps the copy of
          their card you already have but stops it following their changes.
        </p>

        <h2>Report something, or ask for your data</h2>
        <p>
          Mail <a href={`mailto:${CONTACT}`}>{CONTACT}</a>. That is the address
          for abuse reports, a copy of everything we hold on you, privacy
          questions, and anything the answers above do not cover. A person reads
          it.
        </p>

        <p className="legal-footer">
          <a href="/privacy">Privacy Policy</a>
          <span aria-hidden="true"> / </span>
          <a href="/terms">Terms of Service</a>
          <span aria-hidden="true"> / </span>
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a>
        </p>
      </main>
    </div>
  );
}
