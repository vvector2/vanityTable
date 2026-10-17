import { STATUSES, useListings } from "../state/ListingsContext.jsx";

const LABELS = {
  new: "Nowe",
  accepted: "Zaakceptowane",
  rejected: "Odrzucone",
};

export default function StatusTabs() {
  const { tab, setTab, listings } = useListings();

  return (
    <nav className="status-tabs" aria-label="Filtruj ogłoszenia">
      {STATUSES.map((status) => (
        <button
          key={status}
          type="button"
          className={status === tab ? "tab-pill active" : "tab-pill"}
          aria-pressed={status === tab}
          onClick={() => setTab(status)}
        >
          {LABELS[status]} ({listings[status].length})
        </button>
      ))}
    </nav>
  );
}
