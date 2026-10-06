// Satu sumber untuk warna, font, easing, dan spring. Jangan tulis hex di komponen.
import { Easing } from "remotion";

export const theme = {
  colors: {
    bg: "#0A0A0F",
    bgAlt: "#141424",
    primary: "#3B82F6", // warna utama: maksimal satu elemen per frame
    accent: "#22D3EE",
    text: "#F4F4F5",
    textDim: "#A1A1AA",
    glow: "rgba(59, 130, 246, 0.35)",
  },
  fonts: {
    display: "Inter",
    body: "Inter",
  },
  ease: {
    out: Easing.bezier(0.16, 1, 0.3, 1), // masuk
    inOut: Easing.bezier(0.83, 0, 0.17, 1), // gerak panjang
    in: Easing.bezier(0.7, 0, 0.84, 0), // keluar
  },
  spring: {
    snappy: { damping: 14, stiffness: 160, mass: 0.6 },
    smooth: { damping: 20, stiffness: 90, mass: 1 },
  },
} as const;
