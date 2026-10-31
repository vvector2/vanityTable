import HomePage from "./page/HomePage";
import SearchPage from "./page/SearchPage";
import { useRoute } from "./router";

export default function App() {
  const route = useRoute();
  // Keyed by search, so switching searches starts again on the "Nowe" tab.
  return route.page === "search" ? (
    <SearchPage key={route.searchId} searchId={route.searchId} />
  ) : (
    <HomePage />
  );
}
