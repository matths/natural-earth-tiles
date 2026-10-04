export type Theme = "light" | "dark";

/** `styles.css` carries the dark palette on `:root`, so dark needs no attribute. */
const defaultTheme: Theme = "dark";

const isTheme = (value: string | undefined): value is Theme =>
  value === "light" || value === "dark";

export const readTheme = (): Theme => {
  const declared = document.documentElement.dataset.theme;
  return isTheme(declared) ? declared : defaultTheme;
};

export const applyTheme = (theme: Theme): void => {
  document.documentElement.dataset.theme = theme;
};

export const toggleTheme = (theme: Theme): Theme => (theme === "dark" ? "light" : "dark");
