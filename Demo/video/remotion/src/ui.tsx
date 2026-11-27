import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio, Video } from "@remotion/media";

// Shared look: the app's indigo-to-teal palette, system fonts. All timing
// is in seconds, so the video can be rendered at any frame rate.
export const FONT = '"SF Pro Display", -apple-system, "Helvetica Neue", "PingFang SC", sans-serif';
export const TEAL = "#5EE6D9";
export const SOFT = "rgba(226, 232, 255, 0.86)";
export const DIM = "rgba(226, 232, 255, 0.5)";
const OUT = Easing.bezier(0.16, 1, 0.3, 1);
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Seconds since the scene began. */
export const useTime = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return frame / fps;
};

/** 0→1 from `at`, over `seconds`, easing out softly. */
export const useIn = (at: number, seconds = 0.7) => {
  const t = useTime();
  return interpolate(t, [at, at + seconds], [0, 1], { ...clamp, easing: OUT });
};

/** A sound effect (public/sfx/NAME.wav, from make_sfx.py), `at` seconds into the scene. */
export const Sfx: React.FC<{ name: string; at: number; volume?: number; seconds?: number }> = ({ name, at, volume = 0.3, seconds }) => {
  const { fps } = useVideoConfig();
  return (
    <Sequence from={Math.max(0, Math.round(at * fps))} durationInFrames={seconds ? Math.max(1, Math.round(seconds * fps)) : undefined} layout="none">
      <Audio src={staticFile(`sfx/${name}.wav`)} volume={volume} />
    </Sequence>
  );
};

/** Slowly drifting gradient with two soft light blobs. */
export const Background: React.FC = () => {
  const t = useTime();
  return (
    <AbsoluteFill style={{ background: "linear-gradient(135deg, #1c1250 0%, #22195e 35%, #0f3550 75%, #0d4a55 100%)" }}>
      <div
        style={{
          position: "absolute", width: 1100, height: 1100, borderRadius: "50%",
          left: -250 + Math.sin(t / 6) * 120, top: -380 + Math.cos(t / 7) * 80,
          background: "radial-gradient(circle, rgba(124, 92, 255, 0.45), rgba(124, 92, 255, 0) 65%)",
        }}
      />
      <div
        style={{
          position: "absolute", width: 1000, height: 1000, borderRadius: "50%",
          right: -260 + Math.cos(t / 5) * 120, bottom: -420 + Math.sin(t / 8) * 90,
          background: "radial-gradient(circle, rgba(32, 200, 190, 0.32), rgba(32, 200, 190, 0) 65%)",
        }}
      />
    </AbsoluteFill>
  );
};

const PHONE_H = 940;
const PHONE_W = Math.round((PHONE_H * 1320) / 2868);

/** An iPhone that rises in, then floats gently. Its screen is the children. */
export const PhoneFrame: React.FC<{ children: React.ReactNode; x?: number }> = ({ children, x = 250 }) => {
  const t = useTime();
  const appear = useIn(0, 0.9);
  return (
    <div
      style={{
        position: "absolute", left: x, top: (1080 - PHONE_H) / 2 - 14, width: PHONE_W + 28, height: PHONE_H + 28,
        borderRadius: 80, background: "linear-gradient(145deg, #3a3a44, #121217)",
        boxShadow: "0 60px 140px rgba(0,0,0,0.55), 0 0 120px rgba(94,230,217,0.10), inset 0 0 0 2px rgba(255,255,255,0.12)",
        opacity: appear,
        translate: `0px ${interpolate(appear, [0, 1], [70, 0]) + Math.sin(t * 0.9) * 5}px`,
        scale: String(interpolate(appear, [0, 1], [0.96, 1])),
        rotate: `${Math.sin(t * 0.6) * 0.35}deg`,
      }}
    >
      <div style={{ position: "absolute", inset: 14, borderRadius: 66, overflow: "hidden", background: "#000" }}>{children}</div>
    </div>
  );
};

/** The size of the phone's screen in the video, for screens drawn in code. */
export const SCREEN = { width: PHONE_W, height: PHONE_H };

/** An iPhone playing a recording of the app. */
export const Phone: React.FC<{ clip: string; x?: number }> = ({ clip, x }) => (
  <PhoneFrame x={x}>
    <Video src={staticFile(`clips/${clip}.mp4`)} muted style={{ width: "100%", height: "100%", objectFit: "cover" }} />
  </PhoneFrame>
);

export const Rise: React.FC<{ at: number; children: React.ReactNode; distance?: number; seconds?: number }> = ({
  at, children, distance = 30, seconds = 0.7,
}) => {
  const p = useIn(at, seconds);
  return <div style={{ opacity: p, translate: `0px ${(1 - p) * distance}px` }}>{children}</div>;
};

/** A headline whose words come up one after another. */
export const Words: React.FC<{ text: string; at: number; style?: React.CSSProperties; gap?: number }> = ({ text, at, style, gap = 0.07 }) => {
  const t = useTime();
  return (
    <div style={style}>
      {text.split(" ").map((word, i) => {
        const p = interpolate(t, [at + i * gap, at + i * gap + 0.6], [0, 1], { ...clamp, easing: OUT });
        return (
          <span key={i} style={{ display: "inline-block", opacity: p, translate: `0px ${(1 - p) * 26}px`, marginRight: "0.26em" }}>
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** Section label and headline beside the phone. */
export const Heading: React.FC<{ eyebrow: string; title: string; at?: number; size?: number }> = ({ eyebrow, title, at = 0.2, size = 84 }) => (
  <div style={{ fontFamily: FONT }}>
    <Rise at={at}>
      <div style={{ color: TEAL, fontSize: 32, fontWeight: 700, letterSpacing: 5, textTransform: "uppercase" }}>{eyebrow}</div>
    </Rise>
    <Words text={title} at={at + 0.12} style={{ color: "white", fontSize: size, fontWeight: 800, lineHeight: 1.06, marginTop: 16, letterSpacing: -1 }} />
  </div>
);

/** The column of text to the right of the phone. */
export const Side: React.FC<{ children: React.ReactNode; top?: number }> = ({ children, top = 250 }) => (
  <div style={{ position: "absolute", left: 800, top, width: 1000, fontFamily: FONT }}>{children}</div>
);

/** What the user types, shown large, letter by letter. */
export const Typed: React.FC<{ text: string; at: number; perSecond?: number; icon?: string; sound?: boolean }> = ({
  text, at, perSecond = 24, icon = "✦", sound,
}) => {
  const t = useTime();
  const appear = useIn(at, 0.5);
  const chars = Array.from(text);
  const shown = Math.max(0, Math.min(chars.length, Math.floor((t - at - 0.15) * perSecond)));
  const caret = shown < chars.length || Math.floor(t * 2) % 2 === 0;
  return (
    <div
      style={{
        display: "inline-flex", alignItems: "center", gap: 20, padding: "22px 36px", borderRadius: 999, marginTop: 44,
        background: "rgba(124, 92, 255, 0.55)", border: "1.5px solid rgba(255,255,255,0.25)",
        boxShadow: "0 24px 70px rgba(0,0,0,0.3)", fontFamily: FONT, fontSize: chars.length > 34 ? 36 : 44,
        whiteSpace: "nowrap", color: "white", opacity: appear, scale: String(interpolate(appear, [0, 1], [0.94, 1])),
        transformOrigin: "left center",
      }}
    >
      <span style={{ fontSize: 38, opacity: 0.85 }}>{icon}</span>
      <span>
        {chars.slice(0, shown).join("")}
        <span style={{ opacity: caret ? 1 : 0, color: TEAL, marginLeft: 2 }}>|</span>
      </span>
      {sound ? <Sfx name="typing" at={at + 0.15} seconds={chars.length / perSecond} volume={0.22} /> : null}
    </div>
  );
};

/** Steps that light up as the recording reaches them. */
export const Steps: React.FC<{ items: { at: number; text: string }[]; top?: number; sound?: boolean }> = ({ items, top = 44, sound }) => {
  const t = useTime();
  return (
    <div style={{ marginTop: top }}>
      {sound ? items.map((item) => <Sfx key={item.text} name="tick" at={item.at} volume={0.3} />) : null}
      {items.map((item, i) => {
        const p = interpolate(t, [item.at, item.at + 0.6], [0, 1], { ...clamp, easing: OUT });
        const next = items[i + 1]?.at;
        // The step being shown is bright; earlier ones settle back.
        const settle = next === undefined ? 0 : interpolate(t, [next, next + 0.5], [0, 1], clamp);
        return (
          <div
            key={item.text}
            style={{
              display: "flex", alignItems: "center", gap: 24, marginTop: 22, opacity: p * (1 - settle * 0.45),
              translate: `${(1 - p) * -36}px 0px`,
            }}
          >
            <div
              style={{
                width: 18, height: 18, borderRadius: 9, background: TEAL, flexShrink: 0,
                boxShadow: `0 0 ${26 * (1 - settle)}px ${TEAL}`, scale: String(interpolate(p, [0, 1], [0.2, 1])),
              }}
            />
            <div style={{ fontSize: 44, color: "white", lineHeight: 1.25 }}>{item.text}</div>
          </div>
        );
      })}
    </div>
  );
};

/** A result pulled out large: the amount on the receipt, the date found. */
export const Callout: React.FC<{ at: number; label: string; value: string }> = ({ at, label, value }) => {
  const p = useIn(at, 0.8);
  return (
    <div
      style={{
        display: "inline-block", marginTop: 46, padding: "26px 40px", borderRadius: 30, fontFamily: FONT,
        background: "rgba(94,230,217,0.14)", border: `2px solid ${TEAL}`, opacity: p,
        translate: `0px ${(1 - p) * 30}px`, scale: String(interpolate(p, [0, 1], [0.92, 1])), transformOrigin: "left center",
        boxShadow: `0 0 ${70 * p}px rgba(94,230,217,0.22)`,
      }}
    >
      <div style={{ color: TEAL, fontSize: 28, fontWeight: 700, letterSpacing: 3, textTransform: "uppercase" }}>{label}</div>
      <div style={{ color: "white", fontSize: 64, fontWeight: 800, marginTop: 6 }}>{value}</div>
    </div>
  );
};

/** Counts from 0 to `to`, easing out. */
export const Count: React.FC<{ to: number; at: number; seconds?: number; decimals?: number }> = ({ to, at, seconds = 1.3, decimals = 0 }) => {
  const t = useTime();
  const v = interpolate(t, [at, at + seconds], [0, to], { ...clamp, easing: OUT });
  return <>{v.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals })}</>;
};

export const Footnote: React.FC<{ x?: number; text?: string }> = ({ x = 250, text = "Recorded in Phophy, on a demo library" }) => (
  <div
    style={{
      position: "absolute", left: x, bottom: 20, width: PHONE_W + 28, textAlign: "center", fontFamily: FONT,
      fontSize: 19, color: "rgba(226,232,255,0.5)",
    }}
  >
    {text}
  </div>
);
