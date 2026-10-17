import type { Listing } from "../types";

// Sample listings used until the API exists. Shape follows the normalized
// listing from docs/architecture.md plus the stored status and dates.

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

function hoursAgo(hours: number): string {
  return new Date(Date.now() - hours * HOUR).toISOString();
}

function daysAgo(days: number): string {
  return new Date(Date.now() - days * DAY).toISOString();
}

export const sampleListings: Listing[] = [
  {
    olx_id: "1",
    title: "Toaletka retro PRL z lustrem, drewno",
    price: 450,
    location: "Kraków, Bieżanów",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "new",
    is_active: true,
    first_seen_at: hoursAgo(1),
  },
  {
    olx_id: "2",
    title: "Toaletka vintage lata 60. z szufladami",
    price: 380,
    location: "Wieliczka",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "new",
    is_active: true,
    first_seen_at: hoursAgo(6),
  },
  {
    olx_id: "3",
    title: "Toaletka kosmetyczna z trójdzielnym lustrem",
    price: 600,
    location: "Tarnów",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "accepted",
    is_active: true,
    first_seen_at: daysAgo(1),
  },
  {
    olx_id: "4",
    title: "Stara toaletka z taboretem, do renowacji",
    price: 250,
    location: "Katowice",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "rejected",
    is_active: true,
    first_seen_at: daysAgo(1),
  },
  {
    olx_id: "5",
    title: "Toaletka w stylu retro, orzech",
    price: 520,
    location: "Warszawa",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "new",
    is_active: true,
    first_seen_at: daysAgo(2),
  },
  {
    olx_id: "6",
    title: "Toaletka art deco z lustrem",
    price: 800,
    location: "Wrocław",
    url: "https://www.olx.pl/",
    photo_urls: [],
    status: "accepted",
    is_active: false,
    first_seen_at: daysAgo(3),
  },
];

export const sampleLastSyncAt = hoursAgo(0.5);
