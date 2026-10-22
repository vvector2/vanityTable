import { useEffect, useState } from "react";
import { TIMED_OUT_ERROR } from "../api/scanJobs";
import { formatWhen } from "../format";
import { useScan } from "../state/ScanContext";

// After this long the banner warns that the scan is slow; the API fails it at 15 minutes.
const SLOW_AFTER_MS = 5 * 60_000;

function useNow(enabled: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!enabled) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [enabled]);
  return now;
}

function formatElapsed(ms: number): string {
  const seconds = Math.max(0, Math.round(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function ProgressBar() {
  return (
    <div className="scan-progress" aria-hidden="true">
      <i />
    </div>
  );
}

// Progress and result of the followed scan, under the header.
export default function ScanBanner() {
  const { phase, job, alreadyRunning, failure, checkFailed, dismiss } = useScan();
  const now = useNow(phase === "running" || phase === "created");
  const checkNote = checkFailed ? " Nie udało się sprawdzić statusu, ponawiam…" : "";

  if (phase === "starting" || phase === "created") {
    return (
      <>
        <div className="scan-banner" role="status">
          <p className="msg">
            <b>Uruchamianie skanu…</b>
            <span>
              {alreadyRunning && "Skan był już uruchomiony. "}
              Czekam, aż zadanie synchronizacji wystartuje.{checkNote}
            </span>
          </p>
        </div>
        <ProgressBar />
      </>
    );
  }

  if (phase === "running" && job) {
    const elapsed = now - new Date(job.createdAt).getTime();
    return (
      <>
        <div className="scan-banner" role="status">
          <p className="msg">
            <b>Skanowanie OLX…</b>
            <span>
              {alreadyRunning && "Skan był już uruchomiony. "}
              Trwa od {formatElapsed(elapsed)}. Nowe ogłoszenia pojawią się po zakończeniu. Możesz
              dalej przeglądać.
              {elapsed > SLOW_AFTER_MS && " Trwa dłużej niż zwykle; po 15 minutach zostanie przerwany."}
              {checkNote}
            </span>
          </p>
        </div>
        <ProgressBar />
      </>
    );
  }

  if (phase === "succeeded" && job) {
    return (
      <div className="scan-banner ok" role="status">
        <p className="msg">
          <b>Skan zakończony</b>
          <span>
            {job.finishedAt ? `Zakończony ${formatWhen(job.finishedAt)}. ` : ""}Lista jest aktualna.
          </span>
        </p>
      </div>
    );
  }

  if (phase === "failed") {
    const timedOut = job?.error === TIMED_OUT_ERROR;
    let title = "Skan nie powiódł się";
    let detail = failure ?? "Zadanie synchronizacji zgłosiło błąd.";
    if (timedOut) {
      title = "Skan trwał zbyt długo";
      detail = "Brak wyniku w ciągu 15 minut, skan został przerwany.";
    } else if (job?.error) {
      detail = `Szczegóły: ${job.error}`;
    }
    const when = job?.finishedAt ? ` (${formatWhen(job.finishedAt)})` : "";
    return (
      <div className="scan-banner bad" role="alert">
        <p className="msg">
          <b>
            {title}
            {when}
          </b>
          <span>{detail}</span>
        </p>
        <button type="button" className="btn-banner" onClick={dismiss}>
          Zamknij
        </button>
      </div>
    );
  }

  return null;
}
