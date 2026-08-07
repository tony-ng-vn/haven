// The minimal nav shared across public pages and the private preview: Haven at
// left and one contextual action at right. Product links stay out of public
// chrome until they are ready; the preview access point is the honest
// exception.
//
// Absolutely positioned so it drops onto any positioning context (a
// `position: relative` hero, or the other pages' `position: fixed`
// .card-page) without needing to know which.
//
// The mascot icon used to be opt-in, added only for Landing2Page's own
// glass-hero composition; the owner then asked for it on every page, and
// bigger, so it is now unconditional.
//
export function TopNav({
  actionLabel = "Preview access",
  actionHref = "/preview",
  onAction,
}: {
  actionLabel?: string;
  actionHref?: string;
  onAction?: () => void;
}) {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        <img className="top-nav-icon" src="/icon-nav.png" alt="" />
        Haven
      </a>
      <nav aria-label={onAction === undefined ? "Preview" : "Account"}>
        {onAction === undefined ? (
          <a className="top-nav-action" href={actionHref}>
            {actionLabel}
          </a>
        ) : (
          <button className="top-nav-action" type="button" onClick={onAction}>
            {actionLabel}
          </button>
        )}
      </nav>
    </header>
  );
}
