export default function ListingPhoto({ listing, children }) {
  const photo = listing.photo_urls[0];

  return (
    <div className="listing-photo">
      {photo ? (
        <img src={photo} alt={listing.title} loading="lazy" referrerPolicy="no-referrer" />
      ) : (
        <span>Brak zdjęcia</span>
      )}
      {children}
    </div>
  );
}
