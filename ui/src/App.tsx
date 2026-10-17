import Header from "./components/Header";
import ListingGrid from "./components/ListingGrid";
import ReviewView from "./components/ReviewView";
import StatusTabs from "./components/StatusTabs";
import { useListings } from "./state/ListingsContext";

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
