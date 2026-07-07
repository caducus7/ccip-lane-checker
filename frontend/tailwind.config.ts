import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        asphalt: {
          DEFAULT: "#0a0c0f",
          50: "#1a1e24",
          100: "#14181d",
          200: "#0f1216",
        },
        neon: {
          cyan: "#00f5d4",
          amber: "#ffb703",
          red: "#ff3366",
          lime: "#c8f135",
        },
        grid: "#1e2832",
      },
      fontFamily: {
        display: ["var(--font-racing)", "sans-serif"],
        mono: ["var(--font-mono)", "monospace"],
      },
      animation: {
        "pulse-glow": "pulse-glow 2s ease-in-out infinite",
        "lane-dash": "lane-dash 1.2s linear infinite",
        "finish-flash": "finish-flash 0.6s ease-out",
      },
      keyframes: {
        "pulse-glow": {
          "0%, 100%": { opacity: "0.6", filter: "drop-shadow(0 0 4px #00f5d4)" },
          "50%": { opacity: "1", filter: "drop-shadow(0 0 12px #00f5d4)" },
        },
        "lane-dash": {
          to: { strokeDashoffset: "-24" },
        },
        "finish-flash": {
          "0%": { opacity: "0" },
          "50%": { opacity: "1" },
          "100%": { opacity: "0.3" },
        },
      },
      backgroundImage: {
        "checkered":
          "linear-gradient(45deg, #1a1e24 25%, transparent 25%), linear-gradient(-45deg, #1a1e24 25%, transparent 25%), linear-gradient(45deg, transparent 75%, #1a1e24 75%), linear-gradient(-45deg, transparent 75%, #1a1e24 75%)",
      },
      backgroundSize: {
        checkered: "16px 16px",
      },
    },
  },
  plugins: [],
};

export default config;
