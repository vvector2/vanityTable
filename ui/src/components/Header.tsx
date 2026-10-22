import { signOut } from "../auth";
import ScanControl from "./ScanControl";

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

export default function Header() {
  return (
    <header className="app-header">
      <div className="brand">
        <div className="brand-logo">
          <MirrorIcon />
        </div>
        <div>
          <h1>Toaletka finder</h1>
          <p className="brand-tagline">Retro i vintage toaletki z OLX</p>
        </div>
      </div>
      <ScanControl />
      <button type="button" className="btn-sign-out" onClick={() => void signOut()}>
        Wyloguj
      </button>
    </header>
  );
}
