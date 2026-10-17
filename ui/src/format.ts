const priceFormat = new Intl.NumberFormat("pl-PL", {
  style: "currency",
  currency: "PLN",
  maximumFractionDigits: 0,
});

const timeFormat = new Intl.DateTimeFormat("pl-PL", { hour: "2-digit", minute: "2-digit" });

export function formatPrice(price: number | null): string {
  return price == null ? "Cena do uzgodnienia" : priceFormat.format(price);
}

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// "dziś, 14:20", "wczoraj, 09:05", "3 dni temu".
export function formatWhen(iso: string): string {
  const date = new Date(iso);
  const days = Math.round((startOfDay(new Date()) - startOfDay(date)) / 86_400_000);
  if (days <= 0) return `dziś, ${timeFormat.format(date)}`;
  if (days === 1) return `wczoraj, ${timeFormat.format(date)}`;
  return `${days} dni temu`;
}
