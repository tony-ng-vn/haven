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
    <form
      onSubmit={(event) => {
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        void signIn("password", formData);
      }}
    >
      <input name="email" placeholder="Email" type="text" />
      <input name="password" placeholder="Password" type="password" />
      <input name="flow" type="hidden" value={step} />
      <button type="submit">{step === "signIn" ? "Sign in" : "Sign up"}</button>
      <button
        type="button"
        onClick={() => setStep(step === "signIn" ? "signUp" : "signIn")}
      >
        {step === "signIn" ? "Sign up instead" : "Sign in instead"}
      </button>
    </form>
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
        <p>Loading...</p>
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
