import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vite";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

export default defineConfig({
  base: "./",
  server: {
    fs: {
      allow: [repositoryRoot],
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
