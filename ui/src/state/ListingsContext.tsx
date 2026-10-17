import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { sampleLastSyncAt, sampleListings } from "../data/sampleListings";
import type { Listing, ListingStatus } from "../types";

export const STATUSES: readonly ListingStatus[] = ["new", "accepted", "rejected"];

interface ListingsContextValue {
  listings: Record<ListingStatus, Listing[]>;
  lastSyncAt: string | null;
  tab: ListingStatus;
  setTab: (tab: ListingStatus) => void;
  reviewIndex: number;
  current: Listing | null;
  next: () => void;
  prev: () => void;
  decide: (olxId: string, status: ListingStatus) => void;
}

const ListingsContext = createContext<ListingsContextValue | null>(null);

export function ListingsProvider({ children }: { children: ReactNode }) {
  const [listings, setListings] = useState<Listing[]>(sampleListings);
  const [lastSyncAt] = useState<string | null>(sampleLastSyncAt);
  const [tab, setTab] = useState<ListingStatus>("new");
  const [reviewIndex, setReviewIndex] = useState(0);

  const value = useMemo<ListingsContextValue>(() => {
    const byStatus = Object.fromEntries(
      STATUSES.map((status) => [status, listings.filter((l) => l.status === status)]),
    ) as Record<ListingStatus, Listing[]>;
    const newCount = byStatus.new.length;
    // Keep the position valid when the reviewed listing leaves the "new" list.
    const index = newCount ? Math.min(reviewIndex, newCount - 1) : 0;

    return {
      listings: byStatus,
      lastSyncAt,
      tab,
      setTab,
      reviewIndex: index,
      current: byStatus.new[index] ?? null,
      next: () => setReviewIndex(newCount ? (index + 1) % newCount : 0),
      prev: () => setReviewIndex(newCount ? (index - 1 + newCount) % newCount : 0),
      decide: (olxId, status) =>
        setListings((all) => all.map((l) => (l.olx_id === olxId ? { ...l, status } : l))),
    };
  }, [listings, lastSyncAt, tab, reviewIndex]);

  return <ListingsContext.Provider value={value}>{children}</ListingsContext.Provider>;
}

export function useListings(): ListingsContextValue {
  const context = useContext(ListingsContext);
  if (!context) throw new Error("useListings must be used inside ListingsProvider");
  return context;
}
