import type { Listing, ListingStatus } from "../types";
import { apiClient } from "./client";

// Wire format of the listings API (listingApi/app/models.py).
// The API calls the accepted status "saved"; the UI keeps "accepted".
type ApiStatus = "new" | "saved" | "rejected";

interface ListingDto {
  id: string;
  title: string;
  price: number | null;
  currency: string;
  location: string | null;
  url: string;
  images: string[];
  description: string | null;
  status: ApiStatus;
  firstSeenAt: string;
  updatedAt: string;
}

interface ListingsPageDto {
  items: ListingDto[];
  page: number;
  pageSize: number;
  totalItems: number;
  totalPages: number;
}

type ListingCountsDto = Record<ApiStatus, number>;

export interface ListingsPage {
  items: Listing[];
  totalItems: number;
}

const TO_API: Record<ListingStatus, ApiStatus> = {
  new: "new",
  accepted: "saved",
  rejected: "rejected",
};

const FROM_API: Record<ApiStatus, ListingStatus> = {
  new: "new",
  saved: "accepted",
  rejected: "rejected",
};

function toListing(dto: ListingDto): Listing {
  return {
    olx_id: dto.id,
    title: dto.title,
    price: dto.price,
    location: dto.location ?? "",
    url: dto.url,
    photo_urls: dto.images,
    status: FROM_API[dto.status],
    // The API does not report expiry yet, so every listing counts as active.
    is_active: true,
    first_seen_at: dto.firstSeenAt,
  };
}

export async function fetchListings(
  status: ListingStatus,
  { page = 1, pageSize = 50, signal }: { page?: number; pageSize?: number; signal?: AbortSignal } = {},
): Promise<ListingsPage> {
  const { data } = await apiClient.get<ListingsPageDto>("/listings", {
    params: { status: TO_API[status], page, pageSize },
    signal,
  });
  return { items: data.items.map(toListing), totalItems: data.totalItems };
}

export async function fetchCounts(signal?: AbortSignal): Promise<Record<ListingStatus, number>> {
  const { data } = await apiClient.get<ListingCountsDto>("/listings/counts", { signal });
  return { new: data.new, accepted: data.saved, rejected: data.rejected };
}

export async function updateStatus(olxId: string, status: ListingStatus): Promise<Listing> {
  const { data } = await apiClient.put<ListingDto>(
    `/listings/${encodeURIComponent(olxId)}/status`,
    { status: TO_API[status] },
  );
  return toListing(data);
}
