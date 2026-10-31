import { searchHref } from "../router";
import type { Search, SearchCriteria } from "../types";

const COUNT_LABELS = [
  ["new", "Nowe"],
  ["accepted", "Zaakceptowane"],
  ["rejected", "Odrzucone"],
] as const;

const amount = new Intl.NumberFormat("pl-PL", { maximumFractionDigits: 0 });

// "do 600 zł", "od 100 zł", "100–400 zł".
function priceChip({ priceMin, priceMax }: SearchCriteria): string | null {
  if (priceMin != null && priceMax != null) {
    return `${amount.format(priceMin)}–${amount.format(priceMax)} zł`;
  }
  if (priceMax != null) return `do ${amount.format(priceMax)} zł`;
  if (priceMin != null) return `od ${amount.format(priceMin)} zł`;
  return null;
}

// "Warszawa +30 km", or the city alone without a radius.
function locationChip({ location }: SearchCriteria): string | null {
  if (!location) return null;
  return location.radiusKm ? `${location.city} +${location.radiusKm} km` : location.city;
}

function ArrowIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}

export default function SearchCard({ search }: { search: Search }) {
  const { criteria, counts } = search;
  const chips = [...criteria.keywords, priceChip(criteria), locationChip(criteria)].filter(
    (chip): chip is string => Boolean(chip),
  );

  return (
    <article className="search-card card-surface">
      <div className="search-card-top">
        <h3>{search.title}</h3>
        <span className="badge badge-active">
          <span className="sync-dot" />
          Aktywne
        </span>
      </div>
      <div className="chips">
        {chips.map((chip) => (
          <span key={chip} className="chip">
            {chip}
          </span>
        ))}
      </div>
      <div className="counts">
        {COUNT_LABELS.map(([status, label]) => (
          <div
            key={status}
            className={status === "new" && counts.new > 0 ? "count highlight" : "count"}
          >
            <span className="count-num">{counts[status]}</span>
            <span className="count-label">{label}</span>
          </div>
        ))}
      </div>
      <a className="open-search" href={searchHref(search.id)}>
        Otwórz ogłoszenia
        <ArrowIcon />
      </a>
    </article>
  );
}
