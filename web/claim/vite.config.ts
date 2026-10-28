import { defineConfig } from "vite";

// No framework, no CSS-in-JS, no heavy deps: this page has to load fast on a
// cheap phone browser with no app install. Keep it that way — think twice
// before adding a dependency here.
export default defineConfig({
  build: {
    target: "es2018",
    cssMinify: true,
  },
});
