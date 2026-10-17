import { createContext, useContext, useMemo, useState } from "react";
import { sampleLastSyncAt, sampleListings } from "../data/sampleListings.js";

export const STATUSES = ["new", "accepted", "rejected"];

const ListingsContext = createContext(null);

export function ListingsProvider({ children }) {
  const [listings, setListings] = useState(sampleListings);
  const [lastSyncAt] = useState(sampleLastSyncAt);
  const [tab, setTab] = useState("new");
  const [reviewIndex, setReviewIndex] = useState(0);

  const value = useMemo(() => {
    const byStatus = Object.fromEntries(
      STATUSES.map((status) => [status, listings.filter((l) => l.status === status)]),
    );
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

export function useListings() {
  const context = useContext(ListingsContext);
  if (!context) throw new Error("useListings must be used inside ListingsProvider");
  return context;
}
