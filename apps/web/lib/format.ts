export function formatMoney(minorUnits: number, options: { sign?: boolean } = {}) {
  const formatted = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(minorUnits / 100);
  return options.sign && minorUnits > 0 ? `+${formatted}` : formatted;
}

export function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${value}T00:00:00Z`));
}
