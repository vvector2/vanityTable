import { useListings } from "../state/ListingsContext";

// Shows a failed decision. The listing stays where it was, so the user can try again.
export default function ErrorBanner() {
  const { actionError, dismissActionError } = useListings();
  if (!actionError) return null;

  return (
    <div className="error-banner" role="alert">
      <span>{actionError}</span>
      <button type="button" className="btn-dismiss secondary outline" onClick={dismissActionError}>
        Zamknij
      </button>
    </div>
  );
}
