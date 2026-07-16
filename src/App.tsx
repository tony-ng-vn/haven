import { useState } from "react";
import { useAuthActions } from "@convex-dev/auth/react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import type { Id } from "../convex/_generated/dataModel";
import { SearchAdd } from "./SearchAdd";
import { PersonDetail } from "./PersonDetail";

function SignIn() {
  const { signIn } = useAuthActions();
  const [step, setStep] = useState<"signUp" | "signIn">("signIn");
  return (
    <div className="auth">
      <form
        className="auth-card"
        onSubmit={(event) => {
          event.preventDefault();
          const formData = new FormData(event.currentTarget);
          void signIn("password", formData);
        }}
      >
        <span className="auth-brand">Euno</span>
        <p className="auth-tagline">Find your way back to the people you meet.</p>
        <input
          className="auth-input"
          name="email"
          placeholder="Email"
          type="text"
          autoComplete="email"
        />
        <input
          className="auth-input"
          name="password"
          placeholder="Password"
          type="password"
          autoComplete="current-password"
        />
        <input name="flow" type="hidden" value={step} />
        <button className="auth-submit" type="submit">
          {step === "signIn" ? "Sign in" : "Create account"}
        </button>
        <button
          className="auth-toggle"
          type="button"
          onClick={() => setStep(step === "signIn" ? "signUp" : "signIn")}
        >
          {step === "signIn"
            ? "New here? Create an account"
            : "Already have an account? Sign in"}
        </button>
      </form>
    </div>
  );
}

function Home() {
  const { signOut } = useAuthActions();
  const [selectedId, setSelectedId] = useState<Id<"people"> | null>(null);
  return (
    <div className="app">
      <header>
        <span className="brand">Euno</span>
        <button onClick={() => void signOut()}>Sign out</button>
      </header>
      {selectedId === null ? (
        <SearchAdd onOpen={setSelectedId} />
      ) : (
        <PersonDetail id={selectedId} onSaved={() => setSelectedId(null)} />
      )}
    </div>
  );
}

export default function App() {
  return (
    <>
      <AuthLoading>
        <div className="auth">
          <p className="auth-loading">Loading...</p>
        </div>
      </AuthLoading>
      <Unauthenticated>
        <SignIn />
      </Unauthenticated>
      <Authenticated>
        <Home />
      </Authenticated>
    </>
  );
}
