import { useCallback, useEffect, useState } from "react";
import { isCancel } from "axios";
import { errorMessage } from "../api/client";
import { fetchSearches } from "../api/searches";
import { ScanProvider } from "../state/ScanContext";
import type { Search } from "../types";
import Header from "../components/Header";
import ScanBanner from "../components/ScanBanner";
import ScanControl from "../components/ScanControl";
import SearchCard from "../components/SearchCard";

// Free-text box from the Home mockup. The AI chat that turns it into criteria is a later
// feature (docs/SeachCriteria.Feature.md, section 2), so "Szukaj" does nothing yet.
function SearchPrompt() {
  return (
    <section className="search-prompt">
      <label htmlFor="search-prompt">Czego szukasz?</label>
      <textarea
        id="search-prompt"
        rows={5}
        placeholder="Np. retro toaletka z lustrem, jasne drewno, do 600 zł, Warszawa i okolice"
      />
      <div className="search-prompt-row">
        <p className="search-prompt-hint">
          Opisz własnymi słowami, co, w jakiej cenie i gdzie. Jeśli czegoś zabraknie, dopytam.{" "}
          <strong>Już wkrótce.</strong>
        </p>
        <button type="button" className="btn-search" disabled>
          Szukaj
        </button>
      </div>
    </section>
  );
}

function SearchList({ reloadKey, reload }: { reloadKey: number; reload: () => void }) {
  const [searches, setSearches] = useState<Search[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    setSearches(null);
    setLoadError(null);

    fetchSearches(controller.signal)
      .then(setSearches)
      .catch((error: unknown) => {
        if (!isCancel(error)) setLoadError(errorMessage(error));
      });

    return () => controller.abort();
  }, [reloadKey]);

  if (loadError) {
    return (
      <div className="empty-state card-surface load-error" role="alert">
        <p>Nie udało się wczytać wyszukiwań. {loadError}</p>
        <button type="button" className="btn-pager btn-retry" onClick={reload}>
          Spróbuj ponownie
        </button>
      </div>
    );
  }
  if (!searches) {
    return (
      <p className="empty-state" aria-busy="true">
        Wczytywanie wyszukiwań…
      </p>
    );
  }
  if (searches.length === 0) {
    return <p className="empty-state card-surface">Nie masz jeszcze żadnych wyszukiwań.</p>;
  }
  return (
    <div className="search-cards">
      {searches.map((search) => (
        <SearchCard key={search.id} search={search} />
      ))}
    </div>
  );
}

export default function HomePage() {
  const [reloadKey, setReloadKey] = useState(0);
  const reload = useCallback(() => setReloadKey((key) => key + 1), []);

  return (
    <ScanProvider onNewResults={reload}>
      <div className="app">
        <Header>
          <ScanControl />
        </Header>
        <ScanBanner />
        <main className="home-main">
          <SearchPrompt />
          <h2 className="section-title">Moje wyszukiwania</h2>
          <SearchList reloadKey={reloadKey} reload={reload} />
        </main>
      </div>
    </ScanProvider>
  );
}
