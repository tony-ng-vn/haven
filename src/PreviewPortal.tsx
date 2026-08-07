import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  SignIn as ClerkSignIn,
  SignUp as ClerkSignUp,
  useAuth,
  useClerk,
} from "@clerk/react";
import { useMutation, useQuery } from "convex/react";
import { api } from "../convex/_generated/api";
import { DriftSky } from "./DriftSky";
import { Footer } from "./Footer";
import { TopNav } from "./TopNav";
import { SkyPage } from "./SkyPage";
import { CLERK_ROUTING } from "./clerkConfig";
import { isClerkFlowHash, isSkyPath } from "./lib";
import { requestSkyArchive, saveSkyArchive } from "./secureDownload";

const PENDING_CODE_KEY = "haven:previewCode";

function readPendingCode(): string | null {
  try {
    return window.sessionStorage.getItem(PENDING_CODE_KEY);
  } catch {
    return null;
  }
}

function writePendingCode(code: string | null): void {
  try {
    if (code === null) window.sessionStorage.removeItem(PENDING_CODE_KEY);
    else window.sessionStorage.setItem(PENDING_CODE_KEY, code);
  } catch {
    // A blocked session store only means the code must be entered again.
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim() !== "") {
    return error.message;
  }
  return "Something went wrong. Please try again.";
}

export type PreviewAuthMode = "sign-in" | "sign-up" | null;

export function initialPreviewAuthMode(
  pathname: string,
  hash: string,
  pendingCode: string | null,
): PreviewAuthMode {
  const first = pathname.split("/").filter((segment) => segment !== "")[0];
  if (
    first !== undefined &&
    ["signin", "sign-in", "login"].includes(first.toLowerCase())
  ) {
    return "sign-in";
  }
  if (pendingCode !== null) return "sign-up";
  if (isClerkFlowHash(hash)) return "sign-in";
  return null;
}

type PreviewCodeFormProps = {
  onSubmit: (code: string) => Promise<void> | void;
  onSignIn: () => void;
  signInLabel?: string;
  busy?: boolean;
  error?: string | null;
};

export function PreviewCodeForm({
  onSubmit,
  onSignIn,
  signInLabel = "Already have access? Sign in",
  busy = false,
  error = null,
}: PreviewCodeFormProps) {
  const [code, setCode] = useState("");

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalized = code.trim();
    if (normalized !== "") void onSubmit(normalized);
  }

  return (
    <PreviewShell>
      <div className="preview-panel preview-gate">
        <span className="preview-eyebrow">Private preview</span>
        <h1>Preview access</h1>
        <p>
          Haven is still taking shape. Enter your preview code to create an
          account and see what is ready so far.
        </p>
        <form className="preview-form" onSubmit={submit}>
          <label htmlFor="preview-code">Preview code</label>
          <input
            id="preview-code"
            name="preview-code"
            type="text"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            autoComplete="off"
            spellCheck={false}
            required
          />
          {error !== null && (
            <p className="preview-error" role="alert">
              {error}
            </p>
          )}
          <button className="preview-primary" type="submit" disabled={busy}>
            {busy ? "Checking code" : "Continue"}
          </button>
        </form>
        <div className="preview-secondary-actions">
          <button type="button" onClick={onSignIn}>
            {signInLabel}
          </button>
          <a href="/waitlist">I don't have a code</a>
        </div>
      </div>
    </PreviewShell>
  );
}

export function PreviewProfileSetup({
  onCreate,
  onSignOut,
  busy = false,
  error = null,
}: {
  onCreate: (name: string) => Promise<void> | void;
  onSignOut: () => void;
  busy?: boolean;
  error?: string | null;
}) {
  const [name, setName] = useState("");

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalized = name.trim();
    if (normalized !== "") void onCreate(normalized);
  }

  return (
    <PreviewShell privateNav onSignOut={onSignOut}>
      <div className="preview-panel preview-profile">
        <span className="preview-eyebrow">One last thing</span>
        <h1>Welcome to Haven.</h1>
        <p>Your name is all we need to make your Haven profile.</p>
        <form className="preview-form" onSubmit={submit}>
          <label htmlFor="preview-name">Your name</label>
          <input
            id="preview-name"
            name="name"
            type="text"
            value={name}
            onChange={(event) => setName(event.target.value)}
            autoComplete="name"
            required
          />
          {error !== null && (
            <p className="preview-error" role="alert">
              {error}
            </p>
          )}
          <button className="preview-primary" type="submit" disabled={busy}>
            {busy ? "Creating profile" : "Create my profile"}
          </button>
        </form>
      </div>
    </PreviewShell>
  );
}

export function PreviewHome({
  name,
  onSignOut,
}: {
  name?: string;
  onSignOut: () => void;
}) {
  return (
    <PreviewShell privateNav onSignOut={onSignOut}>
      <div className="preview-panel preview-home">
        <span className="preview-eyebrow">
          {name === undefined ? "Your Haven preview" : `Welcome, ${name}`}
        </span>
        <h1>Haven on the web is coming soon.</h1>
        <p>
          Your Haven account is ready. While we build the complete experience,
          you can try Your Sky for Mac.
        </p>
        <div className="preview-home-actions">
          <a className="preview-primary" href="/sky">
            Try Your Sky
          </a>
          <a
            className="preview-book"
            href="https://cal.com/tony-nguyen-vn17"
          >
            Book a call with Tony
          </a>
        </div>
      </div>
    </PreviewShell>
  );
}

function PreviewShell({
  children,
  privateNav = false,
  onSignOut,
}: {
  children: React.ReactNode;
  privateNav?: boolean;
  onSignOut?: () => void;
}) {
  return (
    <div className="card-page preview-page">
      <DriftSky className="card-sky" />
      <TopNav
        actionLabel={privateNav ? "Sign out" : undefined}
        onAction={privateNav ? onSignOut : undefined}
      />
      <main className="preview-main">{children}</main>
      <Footer />
    </div>
  );
}

function AuthPanel({ mode }: { mode: "sign-in" | "sign-up" }) {
  return (
    <PreviewShell>
      <div className="preview-auth-panel">
        {mode === "sign-up" ? (
          <ClerkSignUp routing={CLERK_ROUTING} />
        ) : (
          <ClerkSignIn routing={CLERK_ROUTING} />
        )}
      </div>
    </PreviewShell>
  );
}

export function PreviewPortal({
  pathname,
  hash,
  isAuthenticated,
  isLoading,
}: {
  pathname: string;
  hash: string;
  isAuthenticated: boolean;
  isLoading: boolean;
}) {
  const { signOut } = useClerk();
  const { getToken } = useAuth();
  const checkCode = useMutation(api.previewAccess.checkCode);
  const redeemCode = useMutation(api.previewAccess.redeemCode);
  const updateMyProfile = useMutation(api.profiles.updateMyProfile);
  const hasAccess = useQuery(
    api.previewAccess.hasAccess,
    isAuthenticated ? {} : "skip",
  );
  const [locallyGranted, setLocallyGranted] = useState(false);
  const accessReady = hasAccess === true || locallyGranted;
  const profile = useQuery(
    api.profiles.getMyCard,
    isAuthenticated && accessReady ? {} : "skip",
  );
  const [pendingCode, setPendingCode] = useState(readPendingCode);
  const [authMode, setAuthMode] = useState<PreviewAuthMode>(() =>
    initialPreviewAuthMode(pathname, hash, readPendingCode()),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const redeemAttempt = useRef<string | null>(null);

  useEffect(() => {
    if (
      !isAuthenticated ||
      hasAccess !== false ||
      pendingCode === null ||
      redeemAttempt.current === pendingCode
    ) {
      return;
    }
    redeemAttempt.current = pendingCode;
    setBusy(true);
    void redeemCode({ code: pendingCode })
      .then((result) => {
        writePendingCode(null);
        setPendingCode(null);
        if (result.status === "invalid") {
          setError("That preview code is not valid.");
          return;
        }
        setLocallyGranted(true);
      })
      .catch((caught: unknown) => setError(errorMessage(caught)))
      .finally(() => setBusy(false));
  }, [hasAccess, isAuthenticated, pendingCode, redeemCode]);

  async function submitCode(code: string) {
    setBusy(true);
    setError(null);
    try {
      if (isAuthenticated) {
        const result = await redeemCode({ code });
        if (result.status === "invalid") {
          setError("That preview code is not valid.");
          return;
        }
        setLocallyGranted(true);
        return;
      }

      const result = await checkCode({ code });
      if (result.status === "invalid") {
        setError("That preview code is not valid.");
        return;
      }
      writePendingCode(code);
      setPendingCode(code);
      setAuthMode("sign-up");
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  }

  async function createProfile(name: string) {
    setBusy(true);
    setError(null);
    try {
      await updateMyProfile({ name });
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  }

  async function downloadSky() {
    const archive = await requestSkyArchive((options) => getToken(options));
    saveSkyArchive(archive);
  }

  if (isLoading || (isAuthenticated && hasAccess === undefined)) {
    return (
      <PreviewShell>
        <div className="preview-loading" aria-label="Loading preview" />
      </PreviewShell>
    );
  }
  if (!isAuthenticated) {
    if (authMode !== null) return <AuthPanel mode={authMode} />;
    return (
      <PreviewCodeForm
        onSubmit={submitCode}
        onSignIn={() => setAuthMode("sign-in")}
        busy={busy}
        error={error}
      />
    );
  }
  if (!accessReady) {
    return (
      <PreviewCodeForm
        onSubmit={submitCode}
        onSignIn={() => void signOut()}
        signInLabel="Use another account"
        busy={busy}
        error={error}
      />
    );
  }
  if (profile === undefined) {
    return (
      <PreviewShell privateNav onSignOut={() => void signOut()}>
        <div className="preview-loading" aria-label="Loading profile" />
      </PreviewShell>
    );
  }
  if (profile === null) {
    return (
      <PreviewProfileSetup
        onCreate={createProfile}
        onSignOut={() => void signOut()}
        busy={busy}
        error={error}
      />
    );
  }
  if (isSkyPath(pathname)) {
    return <SkyPage onDownload={downloadSky} onSignOut={() => void signOut()} />;
  }
  return <PreviewHome name={profile.name} onSignOut={() => void signOut()} />;
}
