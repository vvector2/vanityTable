import { formatPrice, formatWhen } from "../format.js";
import { useListings } from "../state/ListingsContext.jsx";
import ListingPhoto from "./ListingPhoto.jsx";

function Badges({ listing }) {
  const accepted = listing.status === "accepted";
  const expired = accepted && !listing.is_active;
  if (!accepted) return null;

  return (
    <div className="badges">
      {expired && <span className="badge badge-expired">Wygasło</span>}
      <span className="badge badge-accepted">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M6 3h12v18l-6-4-6 4z" />
        </svg>
        Zaakceptowane
      </span>
    </div>
  );
}

export default function ListingGrid({ status }) {
  const { listings, decide } = useListings();
  const items = listings[status];

  if (items.length === 0) {
    return <p className="empty-state">Nic tu jeszcze nie ma.</p>;
  }

  return (
    <div className="listing-grid">
      {items.map((listing) => (
        <article
          key={listing.olx_id}
          className={`grid-card card-surface${status === "rejected" ? " is-rejected" : ""}`}
        >
          <ListingPhoto listing={listing}>
            <Badges listing={listing} />
          </ListingPhoto>
          <div className="grid-body">
            <h2>{listing.title}</h2>
            <p className="price">{formatPrice(listing.price)}</p>
            <p className="meta">
              {listing.location} · {formatWhen(listing.first_seen_at)}
            </p>
            <a className="olx-link" href={listing.url} target="_blank" rel="noreferrer">
              Zobacz na OLX →
            </a>
            <button
              type="button"
              className="btn-undo secondary outline"
              onClick={() => decide(listing.olx_id, "new")}
            >
              Przywróć do nowych
            </button>
          </div>
        </article>
      ))}
    </div>
  );
}
