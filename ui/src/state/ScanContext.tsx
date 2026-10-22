import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { isCancel } from "axios";
import {
  fetchLatestScan,
  fetchScanJob,
  isActive,
  isNotFound,
  startErrorMessage,
  startScanJob,
  type ScanJob,
} from "../api/scanJobs";
import { useListings } from "./ListingsContext";

// Id of the job this browser is following. Kept across reloads, so a closed and reopened
// page still shows the result of a scan that ended while it was closed.
const STORAGE_KEY = "toaletka.scanJobId";
// The sync job reports progress through the API; the UI polls while a job is active.
const POLL_MS = 5_000;
// While idle, refresh the last scan time and pick up scheduled runs.
const IDLE_POLL_MS = 60_000;
const SUCCESS_VISIBLE_MS = 6_000;

function readStoredId(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function storeId(id: string | null): void {
  try {
    if (id) localStorage.setItem(STORAGE_KEY, id);
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Storage blocked: the status is then kept only until the page closes.
  }
}

export type ScanPhase = "idle" | "starting" | "created" | "running" | "succeeded" | "failed";

interface ScanContextValue {
  phase: ScanPhase;
  // The followed job: active, or finished and not yet dismissed.
  job: ScanJob | null;
  lastSuccessAt: string | null;
  // POST /scan-job returned a job that was already active.
  alreadyRunning: boolean;
  // Failure on our side (the scan could not be started or its job is gone), in Polish.
  failure: string | null;
  // The last status check failed; polling continues.
  checkFailed: boolean;
  startScan: () => Promise<void>;
  dismiss: () => void;
}

const ScanContext = createContext<ScanContextValue | null>(null);

export function ScanProvider({ children }: { children: ReactNode }) {
  const { reload } = useListings();
  const [job, setJob] = useState<ScanJob | null>(null);
  const [lastSuccessAt, setLastSuccessAt] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [alreadyRunning, setAlreadyRunning] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);
  const [checkFailed, setCheckFailed] = useState(false);
  const lastSuccessRef = useRef<string | null>(null);

  const follow = useCallback((next: ScanJob) => {
    setJob(next);
    storeId(next.id);
  }, []);

  // A newer successful scan means new listings may be in the table.
  const applyLastSuccess = useCallback(
    (at: string | null, refreshList: boolean) => {
      if (at && at !== lastSuccessRef.current && refreshList) reload();
      lastSuccessRef.current = at;
      setLastSuccessAt(at);
    },
    [reload],
  );

  // On load: keep waiting for an active job, or show how the followed job ended.
  useEffect(() => {
    const controller = new AbortController();
    const { signal } = controller;

    (async () => {
      try {
        const latest = await fetchLatestScan(signal);
        applyLastSuccess(latest.lastSuccessAt, false);
        if (latest.activeJob) {
          follow(latest.activeJob);
          return;
        }
        const storedId = readStoredId();
        if (!storedId) return;
        try {
          setJob(await fetchScanJob(storedId, signal));
        } catch (error) {
          // Jobs expire after 3 days; there is nothing left to show.
          if (isNotFound(error)) storeId(null);
          else throw error;
        }
      } catch (error) {
        if (!isCancel(error)) setCheckFailed(true);
      }
    })();

    return () => controller.abort();
  }, [follow, applyLastSuccess]);

  const activeId = job && isActive(job) ? job.id : null;

  // Poll the active job until it succeeds or fails. The API reports a job that has been
  // created or running for 15 minutes as failed, so polling always ends.
  useEffect(() => {
    if (!activeId) return;
    const controller = new AbortController();
    let timer: number | undefined;

    const poll = async () => {
      try {
        const next = await fetchScanJob(activeId, controller.signal);
        setCheckFailed(false);
        setJob(next);
        if (next.status === "succeeded") {
          storeId(null);
          applyLastSuccess(next.finishedAt ?? new Date().toISOString(), true);
        }
        if (isActive(next)) timer = window.setTimeout(poll, POLL_MS);
      } catch (error) {
        if (isCancel(error)) return;
        if (isNotFound(error)) {
          setJob(null);
          storeId(null);
          setFailure("Nie znaleziono zadania skanowania. Spróbuj uruchomić skan ponownie.");
          return;
        }
        // Network or server error: say so and keep trying.
        setCheckFailed(true);
        timer = window.setTimeout(poll, POLL_MS);
      }
    };

    timer = window.setTimeout(poll, POLL_MS);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [activeId, applyLastSuccess]);

  // While idle, refresh the last scan time and start following a run someone else started.
  useEffect(() => {
    if (activeId || starting) return;
    const controller = new AbortController();

    const refresh = async () => {
      if (document.visibilityState !== "visible") return;
      try {
        const latest = await fetchLatestScan(controller.signal);
        setCheckFailed(false);
        applyLastSuccess(latest.lastSuccessAt, true);
        if (latest.activeJob) {
          setFailure(null);
          setAlreadyRunning(false);
          follow(latest.activeJob);
        }
      } catch (error) {
        if (!isCancel(error)) setCheckFailed(true);
      }
    };

    const interval = window.setInterval(refresh, IDLE_POLL_MS);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", refresh);
      controller.abort();
    };
  }, [activeId, starting, follow, applyLastSuccess]);

  // A success message shows briefly; a failure stays until dismissed.
  useEffect(() => {
    if (job?.status !== "succeeded") return;
    const timer = window.setTimeout(() => {
      setJob(null);
      storeId(null);
    }, SUCCESS_VISIBLE_MS);
    return () => window.clearTimeout(timer);
  }, [job]);

  const startScan = useCallback(async () => {
    if (starting || activeId) return;
    setStarting(true);
    setFailure(null);
    setAlreadyRunning(false);
    setJob(null);
    try {
      const started = await startScanJob();
      setAlreadyRunning(started.alreadyRunning);
      follow(started.job);
    } catch (error) {
      setFailure(startErrorMessage(error));
    } finally {
      setStarting(false);
    }
  }, [starting, activeId, follow]);

  const dismiss = useCallback(() => {
    setFailure(null);
    setAlreadyRunning(false);
    setJob(null);
    storeId(null);
  }, []);

  const value = useMemo<ScanContextValue>(() => {
    let phase: ScanPhase = "idle";
    if (starting) phase = "starting";
    else if (failure) phase = "failed";
    else if (job) phase = job.status;
    return { phase, job, lastSuccessAt, alreadyRunning, failure, checkFailed, startScan, dismiss };
  }, [starting, failure, job, lastSuccessAt, alreadyRunning, checkFailed, startScan, dismiss]);

  return <ScanContext.Provider value={value}>{children}</ScanContext.Provider>;
}

export function useScan(): ScanContextValue {
  const context = useContext(ScanContext);
  if (!context) throw new Error("useScan must be used inside ScanProvider");
  return context;
}
