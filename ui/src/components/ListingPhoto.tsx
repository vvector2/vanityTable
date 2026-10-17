import type { ReactNode } from "react";
import type { Listing } from "../types";

interface ListingPhotoProps {
  listing: Listing;
  children?: ReactNode;
}

export default function ListingPhoto({ listing, children }: ListingPhotoProps) {
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
