import { STATUSES, useListings } from "../state/ListingsContext";
import type { ListingStatus } from "../types";

const LABELS: Record<ListingStatus, string> = {
  new: "Nowe",
  accepted: "Zaakceptowane",
  rejected: "Odrzucone",
};

export default function StatusTabs() {
  const { tab, setTab, counts } = useListings();

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
          {LABELS[status]}
          {counts && ` (${counts[status]})`}
        </button>
      ))}
    </nav>
  );
}
