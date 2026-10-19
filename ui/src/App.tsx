import ErrorBanner from "./components/ErrorBanner";
import Header from "./components/Header";
import ListingGrid from "./components/ListingGrid";
import ReviewView from "./components/ReviewView";
import StatusTabs from "./components/StatusTabs";
import { useListings } from "./state/ListingsContext";

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

export default function App() {
  return (
    <div className="app">
      <Header />
      <main className="app-main">
        <StatusTabs />
        <ErrorBanner />
        <TabContent />
      </main>
    </div>
  );
}
