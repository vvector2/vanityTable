import { formatWhen } from "../format";
import { useScan } from "../state/ScanContext";

function RefreshIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M20 11a8 8 0 0 0-14.5-4M4 4v4h4M4 13a8 8 0 0 0 14.5 4M20 20v-4h-4" />
    </svg>
  );
}

function Spinner() {
  return <span className="spin" aria-hidden="true" />;
}

// Last scan time and the "scan now" button in the header. The last successful scan stays
// visible while a scan runs or after one failed, so a broken sync is noticeable.
export default function ScanControl() {
  const { phase, lastSuccessAt, checkFailed, startScan } = useScan();
  const running = phase === "starting" || phase === "created" || phase === "running";
  const lastSuccess = lastSuccessAt ? formatWhen(lastSuccessAt) : null;

  let dot = "ok";
  let text = lastSuccess ? `Ostatni skan: ${lastSuccess}` : "Brak udanego skanu";
  let sub: string | null = null;
  if (running) {
    dot = "run";
    text = "Skan w toku";
    sub = lastSuccess && `Ostatni udany: ${lastSuccess}`;
  } else if (phase === "failed") {
    dot = "bad";
    text = "Ostatni skan nieudany";
    sub = lastSuccess && `Ostatni udany: ${lastSuccess}`;
  } else if (checkFailed) {
    dot = "bad";
    sub = "Nie udało się sprawdzić statusu skanu";
  } else if (!lastSuccess) {
    dot = "bad";
  }

  return (
    <div className="scan">
      <div className="scan-text" role="status" aria-live="polite">
        <span className={`sync-dot ${dot}`} aria-hidden="true" />
        <span>
          {text}
          {sub && <small>{sub}</small>}
        </span>
      </div>
      {running ? (
        <button type="button" className="scan-btn" disabled aria-busy="true">
          <Spinner />
          {phase === "running" ? "Skanowanie…" : "Uruchamianie…"}
        </button>
      ) : (
        <button
          type="button"
          className={phase === "failed" ? "scan-btn retry" : "scan-btn"}
          disabled={phase === "succeeded"}
          onClick={() => void startScan()}
        >
          <RefreshIcon />
          {phase === "failed" ? "Spróbuj ponownie" : "Skanuj teraz"}
        </button>
      )}
    </div>
  );
}
