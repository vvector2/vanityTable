// Decision status shown in the UI. "filtered" listings never reach the UI.
export type ListingStatus = "new" | "accepted" | "rejected";

// Normalized listing from docs/architecture.md plus the stored status and dates.
export interface Listing {
  olx_id: string;
  title: string;
  price: number | null;
  location: string;
  url: string;
  photo_urls: string[];
  status: ListingStatus;
  is_active: boolean;
  first_seen_at: string;
}
