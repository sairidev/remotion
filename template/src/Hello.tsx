import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { theme } from "./theme";

export type HelloProps = {
  title: string;
  subtitle: string;
};

// Lapisan 1: latar gradasi yang bergerak pelan.
const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const x = 50 + Math.sin(t * 0.5) * 18;
  const y = 42 + Math.cos(t * 0.4) * 14;
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(60% 60% at ${x}% ${y}%, ${theme.colors.glow}, transparent 70%), linear-gradient(160deg, ${theme.colors.bgAlt}, ${theme.colors.bg})`,
      }}
    />
  );
};

// Lapisan atas: butiran halus + vignette supaya gambar tidak terasa datar.
const Grain: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ opacity: 0.09, mixBlendMode: "overlay" }}>
      <svg width="100%" height="100%">
        <filter id="grain">
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.9"
            numOctaves={2}
            seed={frame % 12}
          />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
    </AbsoluteFill>
  );
};

const Vignette: React.FC = () => (
  <AbsoluteFill
    style={{
      background:
        "radial-gradient(ellipse at center, transparent 55%, rgba(0,0,0,0.55) 100%)",
    }}
  />
);

// Kata muncul satu per satu: opacity + geser + skala, dengan jeda antar kata.
const Words: React.FC<{ text: string; startAt: number; size: number }> = ({
  text,
  startAt,
  size,
}) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const stagger = Math.round(fps * 0.13);
  const exitStart = durationInFrames - Math.round(fps * 0.4);
  const exit = interpolate(frame, [exitStart, durationInFrames], [0, 1], {
    easing: theme.ease.in,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        justifyContent: "center",
        columnGap: size * 0.26,
        opacity: 1 - exit,
        transform: `translateY(${-exit * size * 0.3}px)`,
      }}
    >
      {text.split(" ").map((word, i) => {
        const enter = spring({
          frame: frame - startAt - i * stagger,
          fps,
          config: theme.spring.snappy,
        });
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: enter,
              transform: `translateY(${(1 - enter) * size * 0.5}px) scale(${
                0.92 + enter * 0.08
              })`,
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

export const Hello: React.FC<HelloProps> = ({ title, subtitle }) => {
  const frame = useCurrentFrame();
  const { fps, width, height, durationInFrames } = useVideoConfig();
  const unit = Math.min(width, height) / 1080; // skala untuk 16:9 dan 9:16
  const titleSize = 104 * unit;
  const subSize = 38 * unit;

  const line = spring({
    frame: frame - Math.round(fps * 0.9),
    fps,
    config: theme.spring.smooth,
  });
  const lineExit = interpolate(
    frame,
    [durationInFrames - Math.round(fps * 0.4), durationInFrames],
    [1, 0],
    {
      easing: theme.ease.in,
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }
  );
  const breathe = 1 + Math.sin((frame / fps) * 1.6) * 0.006;

  return (
    <AbsoluteFill style={{ backgroundColor: theme.colors.bg }}>
      <Background />
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          padding: 96 * unit,
          textAlign: "center",
          transform: `scale(${breathe})`,
        }}
      >
        <div
          style={{
            fontFamily: theme.fonts.display,
            fontWeight: 800,
            fontSize: titleSize,
            lineHeight: 1.05,
            letterSpacing: -titleSize * 0.03,
            color: theme.colors.text,
          }}
        >
          <Words text={title} startAt={Math.round(fps * 0.2)} size={titleSize} />
        </div>
        <div
          style={{
            width: 220 * unit * line * lineExit,
            height: 6 * unit,
            borderRadius: 6 * unit,
            marginTop: 40 * unit,
            marginBottom: 36 * unit,
            backgroundColor: theme.colors.primary,
          }}
        />
        <div
          style={{
            fontFamily: theme.fonts.body,
            fontWeight: 500,
            fontSize: subSize,
            color: theme.colors.textDim,
            maxWidth: 1200 * unit,
          }}
        >
          <Words text={subtitle} startAt={Math.round(fps * 1.2)} size={subSize} />
        </div>
      </AbsoluteFill>
      <Vignette />
      <Grain />
    </AbsoluteFill>
  );
};
