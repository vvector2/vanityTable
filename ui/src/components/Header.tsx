import type { ReactNode } from "react";
import { signOut } from "../auth";

function MirrorIcon() {
  return (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <ellipse cx="12" cy="9" rx="6" ry="7" />
      <path d="M6 21h12M12 16v5" />
    </svg>
  );
}

// children: page controls shown between the brand and the sign-out button.
export default function Header({ children }: { children?: ReactNode }) {
  return (
    <header className="app-header">
      <a className="brand" href="#/">
        <div className="brand-logo">
          <MirrorIcon />
        </div>
        <div>
          <h1>Toaletka finder</h1>
          <p className="brand-tagline">Ogłoszenia z OLX, które pasują do Twoich kryteriów</p>
        </div>
      </a>
      {children}
      <button type="button" className="btn-sign-out" onClick={() => void signOut()}>
        Wyloguj
      </button>
    </header>
  );
}
