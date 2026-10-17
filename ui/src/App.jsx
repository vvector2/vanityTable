import Header from "./components/Header.jsx";
import ListingGrid from "./components/ListingGrid.jsx";
import ReviewView from "./components/ReviewView.jsx";
import StatusTabs from "./components/StatusTabs.jsx";
import { useListings } from "./state/ListingsContext.jsx";

export default function App() {
  const { tab } = useListings();

  return (
    <div className="app">
      <Header />
      <main className="app-main">
        <StatusTabs />
        {tab === "new" ? <ReviewView /> : <ListingGrid status={tab} />}
      </main>
    </div>
  );
}
