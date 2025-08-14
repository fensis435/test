// eslint.config.js
import globals from "globals";
import tseslint from "typescript-eslint";
import pluginReact from "eslint-plugin-react";
import js from "eslint-plugin-js"; // ← 必要なら追加

import { defineConfig } from "eslint/config";

export default defineConfig([
  {
    files: ["**/*.{js,mjs,cjs,ts,mts,cts,jsx,tsx}"],
    plugins: {
      js,
      react: pluginReact,
      "@typescript-eslint": tseslint.plugin
    },
    languageOptions: {
      globals: globals.browser,
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module"
      }
    },
    rules: {
      // ここにルールを追加
      "react/react-in-jsx-scope": "off"
    }
  },
  ...tseslint.configs.recommended,
  ...pluginReact.configs.flat.recommended
]);
