import React from "react";
import { Composition } from "remotion";
import { Hello, HelloProps } from "./Hello";
import "./fonts";

const FPS = 30;
const SECONDS = 5;

const defaultProps: HelloProps = {
  title: "Halo dari Remotion",
  subtitle: "Edit src/Hello.tsx untuk mulai membuat video",
};

// Setiap <Composition> muncul sebagai pilihan bernomor di menu render.
export const Root: React.FC = () => {
  return (
    <>
      <Composition
        id="Hello"
        component={Hello}
        durationInFrames={FPS * SECONDS}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={defaultProps}
      />
      <Composition
        id="HelloVertical"
        component={Hello}
        durationInFrames={FPS * SECONDS}
        fps={FPS}
        width={1080}
        height={1920}
        defaultProps={defaultProps}
      />
    </>
  );
};
