import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: { navy: "#12213B", amber: "#F6A61B", sand: "#F7F4EE" },
    },
  },
  plugins: [],
};
export default config;
