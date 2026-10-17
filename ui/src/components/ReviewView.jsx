import { formatPrice, formatWhen } from "../format.js";
import { useListings } from "../state/ListingsContext.jsx";
import ListingPhoto from "./ListingPhoto.jsx";

export default function ReviewView() {
  const { current, listings, reviewIndex, next, prev, decide } = useListings();

  if (!current) {
    return (
      <p className="empty-state card-surface">
        Wszystko przejrzane. Nowe ogłoszenia pojawią się po następnym skanie.
      </p>
    );
  }

  return (
    <section className="review">
      <article className="review-card card-surface">
        <ListingPhoto listing={current} />
        <div className="review-body">
          <h2>{current.title}</h2>
          <p className="price">{formatPrice(current.price)}</p>
          <p className="meta">
            {current.location} · {formatWhen(current.first_seen_at)}
          </p>
          <a className="olx-link" href={current.url} target="_blank" rel="noreferrer">
            Zobacz na OLX →
          </a>
          <div className="decision-buttons">
            <button
              type="button"
              className="btn-reject"
              onClick={() => decide(current.olx_id, "rejected")}
            >
              Odrzuć
            </button>
            <button
              type="button"
              className="btn-accept"
              onClick={() => decide(current.olx_id, "accepted")}
            >
              Akceptuj
            </button>
          </div>
        </div>
      </article>

      <nav className="pager" aria-label="Przeglądaj nowe ogłoszenia">
        <button type="button" className="btn-pager outline" onClick={prev}>
          ← Poprzednie
        </button>
        <span className="pager-position">
          {reviewIndex + 1} z {listings.new.length}
        </span>
        <button type="button" className="btn-pager" onClick={next}>
          Następne →
        </button>
      </nav>
    </section>
  );
}
