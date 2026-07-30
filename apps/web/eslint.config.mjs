import { FlatCompat } from "@eslint/eslintrc";
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";

const compat = new FlatCompat({
  baseDirectory: import.meta.dirname,
  recommendedConfig: js.configs.recommended,
});

export default defineConfig([
  globalIgnores([
    "**/.next/**",
    "**/.open-next/**",
    "**/out/**",
    "**/build/**",
    "**/next-env.d.ts",
    "**/playwright-report/**",
    "**/test-results/**",
  ]),
  ...compat.extends("next/core-web-vitals", "next/typescript"),
]);
