import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { isCancel } from "axios";
import { errorMessage } from "../api/client";
import { fetchCounts, fetchListings, updateStatus } from "../api/listings";
import type { Listing, ListingStatus } from "../types";

export const STATUSES: readonly ListingStatus[] = ["new", "accepted", "rejected"];

interface ListingsContextValue {
  // Listings of the current tab, newest first.
  items: Listing[];
  counts: Record<ListingStatus, number> | null;
  loading: boolean;
  // Failure to load the current tab; the view shows it instead of the list.
  loadError: string | null;
  // Failure of a decision; shown as a dismissible banner.
  actionError: string | null;
  dismissActionError: () => void;
  reload: () => void;
  // Listing whose decision request is in flight.
  pendingId: string | null;
  tab: ListingStatus;
  setTab: (tab: ListingStatus) => void;
  reviewIndex: number;
  current: Listing | null;
  next: () => void;
  prev: () => void;
  decide: (olxId: string, status: ListingStatus) => Promise<void>;
}

const ListingsContext = createContext<ListingsContextValue | null>(null);

export function ListingsProvider({ children }: { children: ReactNode }) {
  const [tab, setTabState] = useState<ListingStatus>("new");
  const [items, setItems] = useState<Listing[]>([]);
  const [counts, setCounts] = useState<Record<ListingStatus, number> | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [reviewIndex, setReviewIndex] = useState(0);
  const [reloadKey, setReloadKey] = useState(0);

  const reload = useCallback(() => setReloadKey((key) => key + 1), []);

  const setTab = useCallback((next: ListingStatus) => {
    setTabState(next);
    setReviewIndex(0);
  }, []);

  useEffect(() => {
    // Abort the previous tab's request so a slow response cannot overwrite a newer one.
    const controller = new AbortController();
    setLoading(true);
    setLoadError(null);

    fetchListings(tab, { signal: controller.signal })
      .then((page) => setItems(page.items))
      .catch((error: unknown) => {
        if (isCancel(error)) return;
        setItems([]);
        setLoadError(errorMessage(error));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });

    return () => controller.abort();
  }, [tab, reloadKey]);

  useEffect(() => {
    const controller = new AbortController();

    fetchCounts(controller.signal)
      .then(setCounts)
      .catch((error: unknown) => {
        // Counts only feed the tab badges, so a failure keeps the last known counts.
        if (!isCancel(error)) console.warn("Failed to load listing counts", error);
      });

    return () => controller.abort();
  }, [tab, reloadKey]);

  const decide = useCallback(
    async (olxId: string, status: ListingStatus) => {
      setPendingId(olxId);
      setActionError(null);
      try {
        await updateStatus(olxId, status);
        // The status index is eventually consistent, so update locally instead of re-fetching.
        const remaining = items.filter((l) => l.olx_id !== olxId);
        setItems(remaining);
        setCounts((c) => c && { ...c, [tab]: Math.max(0, c[tab] - 1), [status]: c[status] + 1 });
        // Only the first page is loaded; fetch the next batch once it is used up.
        if (remaining.length === 0 && counts && counts[tab] > 1) reload();
      } catch (error) {
        setActionError(errorMessage(error));
      } finally {
        setPendingId(null);
      }
    },
    [items, counts, tab, reload],
  );

  const value = useMemo<ListingsContextValue>(() => {
    const count = items.length;
    // Keep the position valid when the reviewed listing leaves the list.
    const index = count ? Math.min(reviewIndex, count - 1) : 0;

    return {
      items,
      counts,
      loading,
      loadError,
      actionError,
      dismissActionError: () => setActionError(null),
      reload,
      pendingId,
      tab,
      setTab,
      reviewIndex: index,
      current: tab === "new" ? (items[index] ?? null) : null,
      next: () => setReviewIndex(count ? (index + 1) % count : 0),
      prev: () => setReviewIndex(count ? (index - 1 + count) % count : 0),
      decide,
    };
  }, [items, counts, loading, loadError, actionError, reload, pendingId, tab, setTab, reviewIndex, decide]);

  return <ListingsContext.Provider value={value}>{children}</ListingsContext.Provider>;
}

export function useListings(): ListingsContextValue {
  const context = useContext(ListingsContext);
  if (!context) throw new Error("useListings must be used inside ListingsProvider");
  return context;
}
