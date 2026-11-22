import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

// Shared look: the app's indigo-to-teal palette, system fonts.
export const FONT =
  '"SF Pro Display", -apple-system, "Helvetica Neue", "PingFang SC", sans-serif';
export const TEAL = "#5EE6D9";
export const SOFT = "rgba(226, 232, 255, 0.86)";
const OUT = Easing.bezier(0.16, 1, 0.3, 1);

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** 0→1 over `frames`, starting at `start`, with a soft ease-out. */
export const useIn = (start: number, frames = 18) => {
  const frame = useCurrentFrame();
  return interpolate(frame, [start, start + frames], [0, 1], { ...clamp, easing: OUT });
};

/** Slowly drifting gradient with two soft light blobs. */
export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / 30;
  return (
    <AbsoluteFill style={{ background: "linear-gradient(135deg, #1c1250 0%, #22195e 35%, #0f3550 75%, #0d4a55 100%)" }}>
      <div
        style={{
          position: "absolute",
          width: 1100,
          height: 1100,
          borderRadius: "50%",
          left: -250 + Math.sin(t / 6) * 120,
          top: -380 + Math.cos(t / 7) * 80,
          background: "radial-gradient(circle, rgba(124, 92, 255, 0.45), rgba(124, 92, 255, 0) 65%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1000,
          height: 1000,
          borderRadius: "50%",
          right: -260 + Math.cos(t / 5) * 120,
          bottom: -420 + Math.sin(t / 8) * 90,
          background: "radial-gradient(circle, rgba(32, 200, 190, 0.32), rgba(32, 200, 190, 0) 65%)",
        }}
      />
    </AbsoluteFill>
  );
};

export type Shot = {
  /** File in public/shots, without .png */
  src: string;
  /** Frame (within the scene) the shot appears. */
  at: number;
  /** Optional zoom into a point of the 1320×2868 screenshot. */
  zoom?: { x: number; y: number; scale: number; at: number };
};

const PHONE_H = 930;
const PHONE_W = Math.round((PHONE_H * 1320) / 2868);

/** An iPhone showing real app screenshots, cross-fading and zooming. */
export const Phone: React.FC<{ shots: Shot[]; x?: number; enter?: number }> = ({ shots, x = 300, enter = 0 }) => {
  const frame = useCurrentFrame();
  const appear = useIn(enter, 22);
  const visible = shots.filter((s) => s.at <= frame);
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: (1080 - PHONE_H) / 2 - 14,
        width: PHONE_W + 28,
        height: PHONE_H + 28,
        borderRadius: 78,
        background: "linear-gradient(145deg, #3a3a44, #121217)",
        boxShadow: "0 50px 120px rgba(0,0,0,0.55), inset 0 0 0 2px rgba(255,255,255,0.12)",
        opacity: appear,
        translate: `0px ${interpolate(appear, [0, 1], [60, 0])}px`,
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 14,
          borderRadius: 64,
          overflow: "hidden",
          background: "#000",
        }}
      >
        {visible.map((shot, i) => {
          const fadeIn = i === 0 ? 1 : interpolate(frame, [shot.at, shot.at + 10], [0, 1], clamp);
          const z = shot.zoom;
          const zoom = z
            ? interpolate(frame, [z.at, z.at + 24], [1, z.scale], { ...clamp, easing: OUT })
            : 1;
          return (
            <Img
              key={shot.src + shot.at}
              src={staticFile(`shots/${shot.src}.jpg`)}
              style={{
                position: "absolute",
                width: "100%",
                height: "100%",
                objectFit: "cover",
                opacity: fadeIn,
                scale: String(zoom),
                transformOrigin: z ? `${(z.x / 1320) * 100}% ${(z.y / 2868) * 100}%` : "50% 50%",
              }}
            />
          );
        })}
      </div>
    </div>
  );
};

/** Feature name, headline and a few lines, sliding in one after another. */
export const SideText: React.FC<{
  eyebrow: string;
  title: string;
  lines?: string[];
  x?: number;
  start?: number;
}> = ({ eyebrow, title, lines = [], x = 860, start = 6 }) => {
  return (
    <div style={{ position: "absolute", left: x, top: 330, width: 920, fontFamily: FONT }}>
      <Rise at={start}>
        <div style={{ color: TEAL, fontSize: 34, fontWeight: 700, letterSpacing: 4, textTransform: "uppercase" }}>
          {eyebrow}
        </div>
      </Rise>
      <Rise at={start + 6}>
        <div style={{ color: "white", fontSize: 88, fontWeight: 800, lineHeight: 1.05, marginTop: 18 }}>{title}</div>
      </Rise>
      <div style={{ marginTop: 34 }}>
        {lines.map((line, i) => (
          <Rise key={line} at={start + 14 + i * 8}>
            <div style={{ color: SOFT, fontSize: 44, lineHeight: 1.35, marginTop: 10 }}>{line}</div>
          </Rise>
        ))}
      </div>
    </div>
  );
};

export const Rise: React.FC<{ at: number; children: React.ReactNode; distance?: number }> = ({
  at,
  children,
  distance = 28,
}) => {
  const p = useIn(at, 20);
  return <div style={{ opacity: p, translate: `0px ${(1 - p) * distance}px` }}>{children}</div>;
};

/** A search or chat field whose text is typed letter by letter. */
export const TypedField: React.FC<{
  text: string;
  at: number;
  x: number;
  y: number;
  icon?: "search" | "ask";
  until?: number;
}> = ({ text, at, x, y, icon = "search", until }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const appear = useIn(at, 12);
  const leave = until === undefined ? 0 : interpolate(frame, [until, until + 10], [0, 1], clamp);
  const chars = Array.from(text);
  const shown = Math.max(0, Math.min(chars.length, Math.floor((frame - at - 6) / 1.6)));
  const caret = Math.floor(frame / (fps / 2)) % 2 === 0 && shown < chars.length + 6;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        display: "flex",
        alignItems: "center",
        gap: 22,
        padding: "22px 34px",
        borderRadius: 999,
        background: icon === "search" ? "rgba(255,255,255,0.12)" : "rgba(124, 92, 255, 0.85)",
        border: "1.5px solid rgba(255,255,255,0.22)",
        boxShadow: "0 20px 60px rgba(0,0,0,0.3)",
        fontFamily: FONT,
        fontSize: Array.from(text).length > 32 ? 38 : 46,
        whiteSpace: "nowrap",
        color: "white",
        opacity: appear * (1 - leave),
        scale: String(interpolate(appear, [0, 1], [0.94, 1])),
      }}
    >
      <span style={{ fontSize: 42, opacity: 0.85 }}>{icon === "search" ? "⌕" : "✦"}</span>
      <span>
        {chars.slice(0, shown).join("")}
        <span style={{ opacity: caret ? 1 : 0, color: TEAL }}>|</span>
      </span>
    </div>
  );
};

/** A glowing ring drawn around a point of interest on screen. */
export const Ring: React.FC<{ x: number; y: number; w: number; h: number; at: number }> = ({ x, y, w, h, at }) => {
  const p = useIn(at, 16);
  return (
    <div
      style={{
        position: "absolute",
        left: x - 12,
        top: y - 12,
        width: w + 24,
        height: h + 24,
        borderRadius: 26,
        border: `5px solid ${TEAL}`,
        boxShadow: `0 0 40px ${TEAL}`,
        opacity: p,
        scale: String(interpolate(p, [0, 1], [1.12, 1])),
      }}
    />
  );
};

/** Counts from 0 to `to`, easing out. */
export const Count: React.FC<{ to: number; at: number; frames?: number; suffix?: string; decimals?: number }> = ({
  to,
  at,
  frames = 40,
  suffix = "",
  decimals = 0,
}) => {
  const frame = useCurrentFrame();
  const v = interpolate(frame, [at, at + frames], [0, to], { ...clamp, easing: OUT });
  return (
    <>
      {v.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}
      {suffix}
    </>
  );
};
