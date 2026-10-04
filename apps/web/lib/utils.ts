/**
 * Utility function to combine class names
 */
export function cn(...classes: (string | boolean | undefined | null)[]): string {
  return classes.filter(Boolean).join(" ");
}

/**
 * Format timestamp into HH:MM or relative string
 */
export function formatTime(date: Date): string {
  if (!date) return "";
  const d = new Date(date);
  return d.toLocaleTimeString("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
  });
}
