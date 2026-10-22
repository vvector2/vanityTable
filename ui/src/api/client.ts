import axios, { isAxiosError } from "axios";
import { accessToken, userManager } from "../auth";

// Shared Axios instance for the listings API (docs/llstingApi.md).
// VITE_API_URL comes from .env files; see .env.development.
export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? "http://localhost:8000",
  timeout: 10_000,
});

// Every request carries the Cognito access token.
apiClient.interceptors.request.use(async (config) => {
  const token = await accessToken();
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// A rejected token means the session is over: sign in again.
apiClient.interceptors.response.use(undefined, async (error) => {
  if (isAxiosError(error) && error.response?.status === 401) {
    await userManager.removeUser();
    await userManager.signinRedirect();
  }
  return Promise.reject(error);
});

// Turns any request failure into a short Polish message for the UI.
export function errorMessage(error: unknown): string {
  if (!isAxiosError(error)) return "Wystąpił nieoczekiwany błąd.";
  if (error.code === "ECONNABORTED") return "Serwer nie odpowiada. Spróbuj ponownie.";
  if (!error.response) return "Brak połączenia z serwerem.";

  switch (error.response.status) {
    case 401:
      return "Sesja wygasła. Zaloguj się ponownie.";
    case 403:
      return "Brak uprawnień do tej operacji.";
    case 404:
      return "Nie znaleziono ogłoszenia. Mogło zostać usunięte.";
    case 400:
      return "Serwer odrzucił żądanie (błędne dane).";
    default:
      return `Błąd serwera (${error.response.status}). Spróbuj ponownie.`;
  }
}
