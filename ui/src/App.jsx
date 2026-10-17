import { useState } from "react";

const VIEWS = [
  { status: "new", label: "Do przejrzenia" },
  { status: "accepted", label: "Zaakceptowane" },
  { status: "rejected", label: "Odrzucone" },
];

export default function App() {
  const [status, setStatus] = useState("new");

  return (
    <div className="app">
      <header className="header">
        <h1>Toaletka</h1>
        <p className="sync">Ostatnia synchronizacja: brak danych</p>
      </header>

      <nav className="tabs">
        {VIEWS.map((view) => (
          <button
            key={view.status}
            className={view.status === status ? "tab active" : "tab"}
            onClick={() => setStatus(view.status)}
          >
            {view.label}
          </button>
        ))}
      </nav>

      <main>
        <p className="empty">Brak ogłoszeń.</p>
      </main>
    </div>
  );
}
