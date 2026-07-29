import { ClerkProvider, useAuth } from "@clerk/react";
import React from "react";
import ReactDOM from "react-dom/client";
import { ConvexReactClient } from "convex/react";
import { ConvexProviderWithClerk } from "convex/react-clerk";
import App from "./App";
import { ErrorBoundary } from "./ErrorBoundary";
import { clerkAppearance } from "./clerkAppearance";
import { clerkUrlProps } from "./clerkConfig";
import "./index.css";

const convex = new ConvexReactClient(import.meta.env.VITE_CONVEX_URL as string);

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <ClerkProvider
        publishableKey={import.meta.env.VITE_CLERK_PUBLISHABLE_KEY as string}
        appearance={clerkAppearance}
        // Not optional: without these a production instance sends every
        // sign-in redirect to its Account Portal, which sends it back here.
        // See clerkConfig.ts.
        {...clerkUrlProps}
      >
        <ConvexProviderWithClerk client={convex} useAuth={useAuth}>
          <App />
        </ConvexProviderWithClerk>
      </ClerkProvider>
    </ErrorBoundary>
  </React.StrictMode>,
);
