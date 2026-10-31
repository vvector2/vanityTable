import { ListingsProvider, useListings } from "../state/ListingsContext";
import { ScanProvider } from "../state/ScanContext";
import ErrorBanner from "../components/ErrorBanner";
import Header from "../components/Header";
import ListingGrid from "../components/ListingGrid";
import ReviewView from "../components/ReviewView";
import ScanBanner from "../components/ScanBanner";
import ScanControl from "../components/ScanControl";
import StatusTabs from "../components/StatusTabs";

function TabContent() {
  const { tab, loading, loadError, reload } = useListings();

  if (loadError) {
    return (
      <div className="empty-state card-surface load-error" role="alert">
        <p>Nie udało się wczytać ogłoszeń. {loadError}</p>
        <button type="button" className="btn-pager btn-retry" onClick={reload}>
          Spróbuj ponownie
        </button>
      </div>
    );
  }
  if (loading) {
    return (
      <p className="empty-state" aria-busy="true">
        Wczytywanie ogłoszeń…
      </p>
    );
  }
  return tab === "new" ? <ReviewView /> : <ListingGrid status={tab} />;
}

function SearchLayout() {
  const { reload } = useListings();

  return (
    <ScanProvider onNewResults={reload}>
      <div className="app">
        <Header />
        <ScanBanner />
        <main className="app-main">
          <a className="back-link" href="#/">
            ← Moje wyszukiwania
          </a>
          <ScanControl />
          <StatusTabs />
          <ErrorBanner />
          <TabContent />
        </main>
      </div>
    </ScanProvider>
  );
}

// Listings of one saved search: the New, Accepted and Rejected tabs.
export default function SearchPage({ searchId }: { searchId: string }) {
  return (
    <ListingsProvider searchId={searchId}>
      <SearchLayout />
    </ListingsProvider>
  );
}
