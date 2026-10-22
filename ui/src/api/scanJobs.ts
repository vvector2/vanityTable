import { isAxiosError } from "axios";
import { apiClient, errorMessage } from "./client";

// Wire format of the scan-job endpoints (listingApi/app/models.py, ScanJobDto and LatestScanDto).
export type ScanJobStatus = "created" | "running" | "succeeded" | "failed";

export interface ScanJob {
  id: string;
  status: ScanJobStatus;
  createdAt: string;
  finishedAt: string | null;
  error: string | null;
}

export interface LatestScan {
  // Finish time of the newest successful scan; null when none is kept (jobs expire after 3 days).
  lastSuccessAt: string | null;
  // Scan created or running, so a reloaded page keeps waiting for it.
  activeJob: ScanJob | null;
}

// Error the API reports for a job still created or running after 15 minutes (app/scan_jobs.py).
export const TIMED_OUT_ERROR = "No result within 15 minutes";

export function isActive(job: ScanJob): boolean {
  return job.status === "created" || job.status === "running";
}

// 201 starts a new job; 200 returns the job that is already active (started by someone else
// or by the schedule), so OLX sees one run at a time.
export async function startScanJob(): Promise<{ job: ScanJob; alreadyRunning: boolean }> {
  const response = await apiClient.post<ScanJob>("/scan-job");
  return { job: response.data, alreadyRunning: response.status === 200 };
}

export async function fetchScanJob(id: string, signal?: AbortSignal): Promise<ScanJob> {
  const { data } = await apiClient.get<ScanJob>(`/scan-job/${encodeURIComponent(id)}`, { signal });
  return data;
}

export async function fetchLatestScan(signal?: AbortSignal): Promise<LatestScan> {
  const { data } = await apiClient.get<LatestScan>("/scan-job/latest", { signal });
  return data;
}

export function isNotFound(error: unknown): boolean {
  return isAxiosError(error) && error.response?.status === 404;
}

// Polish message for a failed POST /scan-job.
export function startErrorMessage(error: unknown): string {
  if (isAxiosError(error) && error.response?.status === 502) {
    return "Nie udało się uruchomić skanu. Spróbuj ponownie za chwilę.";
  }
  return errorMessage(error);
}
