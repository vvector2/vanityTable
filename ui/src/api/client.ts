import axios, { isAxiosError } from "axios";

// Shared Axios instance for the listings API (docs/llstingApi.md).
// VITE_API_URL and VITE_API_KEY come from .env files; see .env.development.
export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? "http://localhost:8000",
  timeout: 10_000,
  headers: { "X-API-Key": import.meta.env.VITE_API_KEY ?? "" },
});

// Turns any request failure into a short Polish message for the UI.
export function errorMessage(error: unknown): string {
  if (!isAxiosError(error)) return "Wystąpił nieoczekiwany błąd.";
  if (error.code === "ECONNABORTED") return "Serwer nie odpowiada. Spróbuj ponownie.";
  if (!error.response) return "Brak połączenia z serwerem.";

  switch (error.response.status) {
    case 401:
      return "Brak dostępu: nieprawidłowy klucz API.";
    case 404:
      return "Nie znaleziono ogłoszenia. Mogło zostać usunięte.";
    case 400:
      return "Serwer odrzucił żądanie (błędne dane).";
    default:
      return `Błąd serwera (${error.response.status}). Spróbuj ponownie.`;
  }
}
