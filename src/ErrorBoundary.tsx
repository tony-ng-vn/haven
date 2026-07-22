import { Component, type ReactNode } from "react";

// The app's safety net. Without it, one thrown error while React renders
// unmounts the whole tree and leaves a blank screen with no way back. This
// catches that, holds a calm fallback in its place, and offers one quiet retry
// -- so a break stays contained instead of taking Haven down with it.
//
// Error boundaries are the one thing React only supports as a class: the
// static getDerivedStateFromError hook has no function-component equivalent.

type Props = { children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  // Clear the caught error and re-render the children. If whatever broke was
  // transient, the person lands back where they were; if it recurs, the
  // fallback simply returns -- no worse off than before.
  reset = (): void => {
    this.setState({ error: null });
  };

  render(): ReactNode {
    if (this.state.error === null) return this.props.children;
    return (
      <div className="error-boundary" role="alert">
        <div className="error-boundary-card">
          <p className="error-boundary-lead">Oops, sneaky sneaky.</p>
          <p className="error-boundary-body">
            Something tried to sneak into Haven, so we paused things for a
            moment. We are figuring it out and will bring you right back. ^^
          </p>
          <button
            className="error-boundary-retry"
            type="button"
            onClick={this.reset}
          >
            Try again
          </button>
        </div>
      </div>
    );
  }
}
