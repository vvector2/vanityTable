import { useCallback, useEffect, useState } from "react";
import { isCancel } from "axios";
import { errorMessage } from "../api/client";
import { createSearch, fetchSearches } from "../api/searches";
import type { Search } from "../types";
import Header from "../components/Header";
import SearchCard from "../components/SearchCard";

// Free-text box from the Home mockup. The AI chat that turns the text into criteria is a
// later feature (docs/SeachCriteria.Feature.md, section 2). Until then "Szukaj" saves a search
// with fixed criteria; the typed text becomes its title and description.
const FIXED_CRITERIA = {
  keywords: ["toaletka"],
  excludeKeywords: ["toaleta"],
  priceMin: 500,
  priceMax: 3000,
};

function SearchPrompt({ onCreated }: { onCreated: () => void }) {
  const [text, setText] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const trimmed = text.trim();

  async function submit() {
    setSaving(true);
    setSaveError(null);
    try {
      await createSearch({
        title: trimmed.slice(0, 80),
        criteria: { ...FIXED_CRITERIA, description: trimmed.slice(0, 500) },
      });
      setText("");
      onCreated();
    } catch (error: unknown) {
      setSaveError(errorMessage(error));
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="search-prompt">
      <label htmlFor="search-prompt">Czego szukasz?</label>
      <textarea
        id="search-prompt"
        rows={5}
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="Np. retro toaletka z lustrem, jasne drewno, do 600 zł, Warszawa i okolice"
      />
      {saveError && (
        <p className="search-prompt-hint" role="alert">
          Nie udało się zapisać wyszukiwania. {saveError}
        </p>
      )}
      <div className="search-prompt-row">
        <p className="search-prompt-hint">
          Opisz własnymi słowami, co, w jakiej cenie i gdzie. Jeśli czegoś zabraknie, dopytam.{" "}
          <strong>Na razie zapisuję stałe kryteria: toaletka, 500–3000 zł.</strong>
        </p>
        <button
          type="button"
          className="btn-search"
          disabled={!trimmed || saving}
          aria-busy={saving}
          onClick={submit}
        >
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
    <div className="app">
      <Header />
      <main className="home-main">
        <SearchPrompt onCreated={reload} />
        <h2 className="section-title">Moje wyszukiwania</h2>
        <SearchList reloadKey={reloadKey} reload={reload} />
      </main>
    </div>
  );
}
