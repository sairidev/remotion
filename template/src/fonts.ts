import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";
import { theme } from "./theme";

// Font disimpan di public/fonts, jadi render tidak butuh internet.
export const fontsReady = loadFont({
  family: theme.fonts.display,
  url: staticFile("fonts/InterVariable.woff2"),
  weight: "100 900",
});
