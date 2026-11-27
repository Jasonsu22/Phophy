import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useVideoConfig } from "remotion";
import { Callout, Count, DIM, FONT, Footnote, Heading, Phone, PhoneFrame, Rise, SOFT, Sfx, Side, Steps, TEAL, Typed, Words, useIn, useTime } from "./ui";
import { AlbumScreen, Bar, LectureIntroScene, PhotoTile, ThanksScene } from "./scenes";
import timing from "./talk-timing.json";

// Pages of the five-minute presentation: the diagrams and charts that explain
// the motivation, the method, what was built and what was measured, and the
// app recordings with their captions. Each animation is timed to the word of
// the narration it illustrates (the "cues" in talk.json), and has its sound.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const OUT = Easing.bezier(0.16, 1, 0.3, 1);
export const PINK = "#FF9DB0";
const VIOLET = "#B7A8FF";
const LINE = "rgba(226, 232, 255, 0.6)";
const MONO = '"SF Mono", Menlo, Consolas, monospace';
const SIMULATOR = "iPhone 18 Pro Max simulator · demo library";
type Tone = "plain" | "teal" | "pink" | "violet";
const EDGE: Record<Tone, string> = { plain: "rgba(255,255,255,0.17)", teal: "rgba(94,230,217,0.7)", pink: "rgba(255,157,176,0.75)", violet: "rgba(183,168,255,0.7)" };
const FILL: Record<Tone, string> = { plain: "rgba(255,255,255,0.07)", teal: "rgba(94,230,217,0.10)", pink: "rgba(255,157,176,0.10)", violet: "rgba(183,168,255,0.10)" };
const INK: Record<Tone, string> = { plain: "white", teal: TEAL, pink: PINK, violet: VIOLET };

/** When each cue word of a page is spoken, in seconds from the page's start (worked out by make_talk.py). */
const CUES: Record<string, Record<string, number>> = Object.fromEntries(
  (timing.pages as unknown as { id: string; cues?: Record<string, number> }[]).map((page) => [page.id, page.cues ?? {}]),
);
const cuesOf = (page: string) => (name: string, fallback: number) => CUES[page]?.[name] ?? fallback;

// MARK: Building blocks

const Top: React.FC<{ eyebrow: string; title: string; size?: number }> = ({ eyebrow, title, size = 68 }) => (
  <div style={{ position: "absolute", left: 120, top: 62, width: 1680 }}>
    <Heading eyebrow={eyebrow} title={title} at={0.15} size={size} />
  </div>
);

/** A glass card that settles in at `at`, with a sound if one is named. */
const Box: React.FC<{
  x: number; y: number; w: number; h?: number; at: number; tone?: Tone; pad?: string; sound?: string; children?: React.ReactNode;
}> = ({ x, y, w, h, at, tone = "plain", pad = "26px 32px", sound, children }) => {
  const p = useIn(at, 0.6);
  return (
    <div
      style={{
        position: "absolute", left: x, top: y, width: w, height: h, boxSizing: "border-box", padding: pad, borderRadius: 28,
        background: FILL[tone], border: `2px solid ${EDGE[tone]}`, boxShadow: "0 24px 70px rgba(0,0,0,0.26)", fontFamily: FONT,
        opacity: p, translate: `0px ${(1 - p) * 26}px`, scale: String(0.96 + 0.04 * p),
      }}
    >
      {children}
      {sound ? <Sfx name={sound} at={at} volume={0.3} /> : null}
    </div>
  );
};

/** An arrow that draws itself from one point to another. */
const Arrow: React.FC<{ from: [number, number]; to: [number, number]; at: number; color?: string; dashed?: boolean; label?: string; labelDy?: number }> = ({
  from, to, at, color = LINE, dashed, label, labelDy = -14,
}) => {
  const p = useIn(at, 0.55);
  const x = from[0] + (to[0] - from[0]) * p;
  const y = from[1] + (to[1] - from[1]) * p;
  const angle = (Math.atan2(to[1] - from[1], to[0] - from[0]) * 180) / Math.PI;
  return (
    <svg width={1920} height={1080} style={{ position: "absolute", left: 0, top: 0, overflow: "visible", opacity: Math.min(1, p * 4) }}>
      <line x1={from[0]} y1={from[1]} x2={x} y2={y} stroke={color} strokeWidth={4} strokeLinecap="round" strokeDasharray={dashed ? "2 12" : undefined} />
      <polygon points="0,0 -18,-10 -18,10" fill={color} transform={`translate(${x},${y}) rotate(${angle})`} />
      {label ? (
        <text x={(from[0] + to[0]) / 2} y={(from[1] + to[1]) / 2 + labelDy} textAnchor="middle" fontFamily={FONT} fontSize={24} fill={color} opacity={p}>
          {label}
        </text>
      ) : null}
    </svg>
  );
};

const ICONS: Record<string, React.ReactNode> = {
  search: <><circle cx={21} cy={21} r={12} /><path d="M30 30l12 12" /></>,
  chat: <path d="M9 9h30a4 4 0 0 1 4 4v16a4 4 0 0 1-4 4H23l-10 8v-8H9a4 4 0 0 1-4-4V13a4 4 0 0 1 4-4z" />,
  book: <><path d="M6 10c6-3 12-3 18 0v30c-6-3-12-3-18 0z" /><path d="M24 10c6-3 12-3 18 0v30c-6-3-12-3-18 0z" /></>,
  sliders: <><path d="M6 13h36M6 24h36M6 35h36" /><circle cx={17} cy={13} r={4.5} fill="#221a5c" /><circle cx={32} cy={24} r={4.5} fill="#221a5c" /><circle cx={21} cy={35} r={4.5} fill="#221a5c" /></>,
  cloud: <path d="M14 37a9 9 0 0 1 .5-18A12 12 0 0 1 38 21a8 8 0 0 1-1 16z" />,
  lock: <><rect x={10} y={22} width={28} height={20} rx={4} /><path d="M16 22v-6a8 8 0 0 1 16 0v6" /></>,
  photo: <><rect x={5} y={9} width={38} height={30} rx={5} /><circle cx={16} cy={19} r={3.5} /><path d="M5 34l12-10 9 7 6-5 11 9" /></>,
  tag: <><path d="M6 8h17l19 19-15 15L8 23z" /><circle cx={16} cy={17} r={3} /></>,
  bars: <path d="M8 40V26M16 40V12M24 40V30M32 40V18M40 40V24" />,
  pen: <><path d="M8 40l3-11 22-22 8 8-22 22z" /><path d="M28 12l8 8" /></>,
  db: <><ellipse cx={24} cy={11} rx={16} ry={6} /><path d="M8 11v26c0 3.3 7.2 6 16 6s16-2.7 16-6V11" /><path d="M8 24c0 3.3 7.2 6 16 6s16-2.7 16-6" /></>,
  phone: <><rect x={13} y={4} width={22} height={40} rx={5} /><path d="M20 38h8" /></>,
  check: <path d="M9 25l10 10 20-22" />,
  chip: <><rect x={12} y={12} width={24} height={24} rx={4} /><path d="M18 5v7M30 5v7M18 36v7M30 36v7M5 18h7M5 30h7M36 18h7M36 30h7" /></>,
  grid: <><rect x={6} y={6} width={15} height={15} rx={3} /><rect x={27} y={6} width={15} height={15} rx={3} /><rect x={6} y={27} width={15} height={15} rx={3} /><rect x={27} y={27} width={15} height={15} rx={3} /></>,
  clock: <><circle cx={24} cy={24} r={17} /><path d="M24 13v12l8 5" /></>,
};

const Icon: React.FC<{ name: string; size?: number; color?: string }> = ({ name, size = 48, color = TEAL }) => (
  <svg width={size} height={size} viewBox="0 0 48 48" fill="none" stroke={color} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
    {name === "text" ? (
      <text x={24} y={35} textAnchor="middle" fontSize={30} fontWeight={700} fill={color} stroke="none" fontFamily={FONT}>Aa</text>
    ) : (
      ICONS[name]
    )}
  </svg>
);

const Chip: React.FC<{ children: React.ReactNode; tone?: Tone; size?: number; label?: string }> = ({ children, tone = "plain", size = 28, label }) => (
  <span
    style={{
      display: "inline-flex", alignItems: "baseline", gap: 12, padding: "9px 22px", borderRadius: 999, fontSize: size, fontFamily: FONT,
      color: INK[tone], background: FILL[tone], border: `1.5px solid ${tone === "plain" ? "rgba(255,255,255,0.24)" : EDGE[tone]}`, whiteSpace: "nowrap",
    }}
  >
    {label ? <span style={{ fontSize: size * 0.62, letterSpacing: 2, opacity: 0.75, fontWeight: 700 }}>{label}</span> : null}
    {children}
  </span>
);

const Thumb: React.FC<{ src: string; w: number; h: number; rank?: number; best?: boolean }> = ({ src, w, h, rank, best }) => (
  <div style={{ position: "relative", width: w, height: h, flexShrink: 0 }}>
    <Img
      src={staticFile(src)}
      style={{
        width: w, height: h, objectFit: "cover", borderRadius: 16, display: "block",
        border: `3px solid ${best ? TEAL : "rgba(255,255,255,0.75)"}`, boxShadow: best ? "0 0 46px rgba(94,230,217,0.45)" : "0 14px 34px rgba(0,0,0,0.4)",
        boxSizing: "border-box",
      }}
    />
    {rank ? (
      <div
        style={{
          position: "absolute", left: -12, top: -12, width: 40, height: 40, borderRadius: 20, background: best ? TEAL : "#2a2168",
          border: "2px solid rgba(255,255,255,0.8)", color: best ? "#0d2b3a" : "white", fontFamily: FONT, fontWeight: 800, fontSize: 22,
          textAlign: "center", lineHeight: "37px",
        }}
      >
        {rank}
      </div>
    ) : null}
  </div>
);

// MARK: Opening

export const TitleTalk: React.FC = () => (
  <AbsoluteFill>
    {Array.from({ length: 18 }, (_, i) => (
      <PhotoTile key={i} n={i + 1} i={i} />
    ))}
    <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 50%, rgba(20,14,60,0.78), rgba(20,14,60,0.35) 70%)" }} />
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, textAlign: "center" }}>
      <Rise at={0.3} distance={46} seconds={1}>
        <div style={{ fontSize: 196, fontWeight: 800, color: "white", letterSpacing: -4 }}>Phophy</div>
      </Rise>
      <Words text="Your photos, understood. On your iPhone." at={0.8} style={{ fontSize: 54, color: SOFT, marginTop: 6 }} />
      <Rise at={1.6}>
        <div style={{ fontSize: 32, color: TEAL, marginTop: 70, fontWeight: 700, letterSpacing: 4 }}>TEAM 26 · COMP7607 PROJECT</div>
      </Rise>
    </AbsoluteFill>
    <Sfx name="chime" at={0.9} volume={0.2} />
  </AbsoluteFill>
);

// MARK: Motivation

/** Scenario 1: a travel photo remembered only by three vague things, and a library too long to scroll. */
export const HuntTalk: React.FC = () => {
  const t = useTime();
  const { durationInFrames, fps } = useVideoConfig();
  const total = durationInFrames / fps;
  const cue = cuesOf("scenario1");
  const giveUpAt = cue("giveup", total - 2.2) + 0.5;
  // The scrolling fills the page: up through the months, back down, up again.
  const pace = (total - 1.2) / 12.6;
  const starts = [0.9, 2.4, 3.9, 5.5, 7.0, 8.4, 9.8, 11.1].map((s) => s * pace);
  const plan = (bottom: number) =>
    [bottom - 760, bottom - 1650, bottom - 2600, 120, 1150, 2100, 1500, 2700].map((to, i) => [starts[i], 1.45 * pace, to]);
  const looked = interpolate(t, [1.6, giveUpAt], [0, 192], clamp);
  const giveUp = useIn(giveUpAt, 0.7);
  const memories: [string, string][] = [["snow", "snow"], ["hat", "a white hat"], ["smile", "a big smile"]];
  return (
    <AbsoluteFill>
      <PhoneFrame>
        <AlbumScreen plan={plan} />
      </PhoneFrame>
      <Side top={170}>
        <Heading eyebrow="Scenario 1" title="“Where is that photo from the ski trip?”" size={74} />
        <Rise at={cue("remember", 5) - 0.2}>
          <div style={{ marginTop: 44, fontSize: 38, color: SOFT }}>All you remember:</div>
        </Rise>
        <div style={{ display: "flex", gap: 18, marginTop: 20 }}>
          {memories.map(([name, text], i) => (
            <Rise key={name} at={cue(name, 6 + i * 0.7)}>
              <Chip tone="teal" size={40}>{text}</Chip>
              <Sfx name="pop" at={cue(name, 6 + i * 0.7)} volume={0.3} />
            </Rise>
          ))}
        </div>
        <Rise at={1.9}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 26, marginTop: 40 }}>
            <div style={{ fontSize: 112, fontWeight: 800, color: "white", fontVariantNumeric: "tabular-nums" }}>
              {Math.floor(looked / 60)}:{String(Math.floor(looked % 60)).padStart(2, "0")}
            </div>
            <div style={{ fontSize: 40, color: DIM }}>of scrolling</div>
          </div>
        </Rise>
        <div style={{ opacity: giveUp, translate: `0px ${(1 - giveUp) * 24}px`, marginTop: 12, fontSize: 46, fontWeight: 700, color: "#FFB4A8" }}>
          Still not found. It is buried.
        </div>
      </Side>
      <Footnote text="The library, drawn as an animation" />
      {starts.map((s) => (
        <Sfx key={s} name="swipe" at={s} volume={0.22} />
      ))}
      <Sfx name="low" at={giveUpAt} volume={0.32} />
    </AbsoluteFill>
  );
};

/** Scenario 2: the slides, dealt as they are photographed and swept away as "never open them again" is said. */
export const LectureTalk: React.FC = () => {
  const cue = cuesOf("scenario2");
  const deal = cue("slides", 2.6) - 0.1;
  const pile = cue("never", 5.6) - 0.3;
  return (
    <>
      <LectureIntroScene dealAt={deal} pileAt={pile} />
      {[0, 2, 4, 6].map((i) => (
        <Sfx key={i} name="shutter" at={deal + 0.15 + i * 0.12} volume={0.28} />
      ))}
      <Sfx name="whoosh" at={pile} volume={0.22} />
      <Sfx name="low" at={pile + 1} volume={0.3} />
    </>
  );
};

const Mark: React.FC<{ ok: boolean }> = ({ ok }) => (
  <svg width={44} height={44} viewBox="0 0 48 48" style={{ flexShrink: 0 }}>
    <circle cx={24} cy={24} r={21} fill={ok ? "rgba(94,230,217,0.16)" : "rgba(255,157,176,0.16)"} stroke={ok ? TEAL : PINK} strokeWidth={2.5} />
    <path d={ok ? "M14 25l7 7 14-15" : "M16 16l16 16M32 16L16 32"} fill="none" stroke={ok ? TEAL : PINK} strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

const CheckLine: React.FC<{ at: number; ok: boolean; children: React.ReactNode }> = ({ at, ok, children }) => (
  <Rise at={at} distance={16} seconds={0.5}>
    <div style={{ display: "flex", alignItems: "center", gap: 22, marginTop: 30, fontSize: 35, color: ok ? "white" : SOFT, lineHeight: 1.25 }}>
      <Mark ok={ok} />
      <div>{children}</div>
    </div>
    <Sfx name="tick" at={at} volume={0.3} />
  </Rise>
);

const CardHead: React.FC<{ icon: string; title: string }> = ({ icon, title }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
    <Icon name={icon} size={58} />
    <div style={{ fontSize: 44, fontWeight: 800, color: "white" }}>{title}</div>
  </div>
);

export const WhyScene: React.FC = () => {
  const cue = cuesOf("why");
  const builtin = cue("builtin", 2);
  const cloud = cue("cloud", 7.5);
  const lineAt = cue("private", 11) + 1.5;
  const line = useIn(lineAt, 0.8);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="The problem" title="Why today’s tools don’t solve it" />
      <Box x={120} y={300} w={820} h={490} at={builtin - 0.4} pad="38px 44px" sound="pop">
        <CardHead icon="search" title="Built-in photo search" />
        <CheckLine at={builtin + 0.9} ok>Dates and places</CheckLine>
        <CheckLine at={cue("labels", 4.2)} ok>A fixed set of labels: “dog”, “beach”</CheckLine>
        <CheckLine at={cue("not", 5.6)} ok={false}>“the ski photo with the white hat”</CheckLine>
        <CheckLine at={cue("not", 5.6) + 0.6} ok={false}>“the slides from today’s lecture”</CheckLine>
      </Box>
      <Box x={980} y={300} w={820} h={490} at={cloud - 0.3} pad="38px 44px" sound="pop">
        <CardHead icon="cloud" title="A cloud AI on every photo" />
        <CheckLine at={cue("slow", 9.6)} ok={false}>Slow for a library of 10,000 photos</CheckLine>
        <CheckLine at={cue("costly", 10.3)} ok={false}>Costs money for every photo</CheckLine>
        <CheckLine at={cue("private", 11)} ok={false}>Uploads your private photos</CheckLine>
      </Box>
      <div
        style={{
          position: "absolute", left: 120, top: 850, width: 1680, textAlign: "center", fontSize: 44, fontWeight: 700, color: TEAL,
          opacity: line, translate: `0px ${(1 - line) * 22}px`,
        }}
      >
        We want search by description, without giving the photos away.
      </div>
    </AbsoluteFill>
  );
};

export const GoalScene: React.FC = () => {
  const cue = cuesOf("goal");
  const tiles = [
    ["search", "Find", "any photo, by describing it", "find"],
    ["chat", "Ask", "questions about what’s in a photo", "ask"],
    ["book", "Study", "notes and flashcards from slide photos", "study"],
    ["sliders", "Edit", "a photo by typing the change", "edit"],
  ];
  const chips: [string, Tone][] = [["English and 中文", "teal"], ["On-device first, cloud only if you allow it", "plain"], ["Works without Apple Intelligence", "plain"]];
  const chipsAt = cue("langs", 8.5);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Our goal" title="Understand every photo, on the phone itself" size={72} />
      {tiles.map(([icon, verb, line, name], i) => (
        <Box key={verb} x={120 + i * 425} y={350} w={395} h={340} at={cue(name, 5.5 + i * 0.5) - 0.15} pad="38px 36px" sound="pop">
          <Icon name={icon} size={72} />
          <div style={{ fontSize: 62, fontWeight: 800, color: "white", marginTop: 22 }}>{verb}</div>
          <div style={{ fontSize: 31, color: SOFT, marginTop: 10, lineHeight: 1.3 }}>{line}</div>
        </Box>
      ))}
      <div style={{ position: "absolute", left: 120, top: 760, width: 1680, display: "flex", gap: 22, justifyContent: "center" }}>
        {chips.map(([text, tone], i) => (
          <Rise key={text} at={chipsAt + i * 0.35}>
            <Chip tone={tone} size={32}>{text}</Chip>
          </Rise>
        ))}
      </div>
      <Sfx name="chime" at={chipsAt} volume={0.2} />
    </AbsoluteFill>
  );
};

// MARK: Methodology

const TIERS = [
  { n: "0", name: "Metadata", what: "date, place, kind of photo", by: "PhotoKit" },
  { n: "1", name: "Text and labels", what: "text recognition, scene labels", by: "Apple Vision" },
  { n: "2", name: "Embedding", what: "one vector per photo", by: "MobileCLIP, through Core ML" },
  { n: "3", name: "On-device model", what: "descriptions, notes, reading requests", by: "Apple Intelligence or SmolVLM2" },
  { n: "4", name: "Cloud model", what: "the assistant and notes, text only", by: "your chosen API" },
];

export const TiersScene: React.FC = () => {
  const cue = cuesOf("tiers");
  // Each tier arrives as the narration names it.
  const at = [cue("t0", 8.6), cue("t1", 9.4), cue("t2", 10.6), cue("t3", 11.6), cue("t4", 13.4)].map((s) => s - 0.15);
  const bracket = useIn(cue("once", 5.2), 0.8);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Key idea" title="Tiered processing: the cheapest tool first" />
      <div
        style={{
          position: "absolute", left: 120, top: 282, width: 84, height: 500, borderRadius: 24, boxSizing: "border-box",
          background: "rgba(94,230,217,0.10)", border: "2px solid rgba(94,230,217,0.6)", opacity: bracket,
          display: "flex", alignItems: "center", justifyContent: "center",
        }}
      >
        <div style={{ writingMode: "vertical-rl", rotate: "180deg", color: TEAL, fontSize: 21, fontWeight: 700, letterSpacing: 2, whiteSpace: "nowrap" }}>
          ON THE IPHONE · ONCE PER PHOTO
        </div>
      </div>
      {TIERS.map((tier, i) => {
        const cloud = i === 4;
        return (
          <Box key={tier.n} x={cloud ? 120 : 226} y={282 + i * 129 + (cloud ? 14 : 0)} w={cloud ? 1680 : 1574} h={113} at={at[i]} tone={cloud ? "pink" : "plain"} pad="0 28px" sound={`note${i + 1}`}>
            <div style={{ display: "flex", alignItems: "center", gap: 22, height: "100%" }}>
              <div
                style={{
                  width: 58, height: 58, borderRadius: 29, flexShrink: 0, textAlign: "center", lineHeight: "56px", fontSize: 30, fontWeight: 800,
                  color: cloud ? PINK : TEAL, border: `2.5px solid ${cloud ? PINK : TEAL}`, boxSizing: "border-box",
                }}
              >
                {tier.n}
              </div>
              <div style={{ width: cloud ? 440 : 334, flexShrink: 0, fontSize: 36, fontWeight: 700, color: "white" }}>{tier.name}</div>
              <div style={{ width: 500, flexShrink: 0, fontSize: 29, color: SOFT, lineHeight: 1.25 }}>{tier.what}</div>
              <div style={{ flex: 1, minWidth: 0, fontSize: 27, color: DIM, lineHeight: 1.25 }}>{tier.by}</div>
              <div style={{ flexShrink: 0 }}>
                <Chip tone={cloud ? "pink" : "teal"} size={27}>{cloud ? "Optional · pay per use" : "Free"}</Chip>
              </div>
            </div>
          </Box>
        );
      })}
    </AbsoluteFill>
  );
};

const Reader: React.FC<{ y: number; at: number; icon: string; title: string; note: string; children: React.ReactNode }> = ({ y, at, icon, title, note, children }) => (
  <Box x={730} y={y} w={650} h={116} at={at} pad="13px 24px" sound="tick">
    <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
      <Icon name={icon} size={40} />
      <div style={{ fontSize: 29, fontWeight: 700, color: "white" }}>{title}</div>
      <div style={{ fontSize: 22, color: DIM, marginLeft: "auto" }}>{note}</div>
    </div>
    <div style={{ marginTop: 8, fontSize: 25, color: SOFT, whiteSpace: "nowrap", overflow: "hidden" }}>{children}</div>
  </Box>
);

export const IndexScene: React.FC = () => {
  const cue = cuesOf("index");
  const photo = useIn(0.7, 0.8);
  const ys = [262, 392, 522, 652, 782];
  const at = [cue("when", 3), cue("text", 5.4), cue("tags", 7), cue("emb", 9.6), cue("desc", 11.6)].map((s) => s - 0.1);
  const dbAt = cue("db", 15.4);
  const stored = useIn(dbAt, 0.8);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Indexing" title="Every photo is read once, on the phone" />
      <div style={{ position: "absolute", left: 120, top: 410, opacity: photo, translate: `${(1 - photo) * -40}px 0px` }}>
        <Thumb src="talk/ski.jpg" w={480} h={320} />
        <div style={{ marginTop: 18, fontSize: 27, color: DIM, width: 480, textAlign: "center" }}>The photo from the ski trip</div>
      </div>
      {ys.map((y, i) => (
        <Arrow key={y} from={[612, 570]} to={[722, y + 58]} at={at[i] - 0.35} />
      ))}
      <Reader y={ys[0]} at={at[0]} icon="clock" title="When and where" note="from the photo itself">13 January 2026 · Zermatt, Switzerland</Reader>
      <Reader y={ys[1]} at={at[1]} icon="text" title="Text in the photo" note="Apple Vision">
        <span style={{ color: DIM }}>none in this one; on a receipt or a slide, every word</span>
      </Reader>
      <Reader y={ys[2]} at={at[2]} icon="tag" title="Tags" note="4,585 concepts">
        <span style={{ display: "inline-flex", gap: 10 }}>
          {["skier", "滑雪", "ski pole", "滑雪杖"].map((tag) => (
            <Chip key={tag} tone="teal" size={21}>{tag}</Chip>
          ))}
        </span>
      </Reader>
      <Reader y={ys[3]} at={at[3]} icon="bars" title="Embedding" note="MobileCLIP · 512 numbers">
        <span style={{ display: "inline-flex", alignItems: "flex-end", gap: 5, height: 34 }}>
          {Array.from({ length: 44 }, (_, i) => (
            <span key={i} style={{ width: 8, height: 6 + Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.6)) * 28, borderRadius: 3, background: TEAL, opacity: 0.45 + (i % 3) * 0.2 }} />
          ))}
        </span>
      </Reader>
      <Reader y={ys[4]} at={at[4]} icon="pen" title="Description" note="on-device model">“A woman in a winter outfit skiing in the snow.”</Reader>
      {ys.map((y, i) => (
        <Arrow key={y} from={[1388, y + 58]} to={[1494, 590]} at={dbAt - 0.7 + i * 0.1} color="rgba(94,230,217,0.8)" />
      ))}
      <div
        style={{
          position: "absolute", left: 1500, top: 440, width: 300, textAlign: "center", opacity: stored,
          scale: String(0.9 + 0.1 * stored), filter: `drop-shadow(0 0 ${40 * stored}px rgba(94,230,217,0.35))`,
        }}
      >
        <Icon name="db" size={190} />
        <div style={{ fontSize: 40, fontWeight: 800, color: "white", marginTop: 8 }}>Local index</div>
        <div style={{ fontSize: 27, color: SOFT, marginTop: 6 }}>a database on the iPhone</div>
      </div>
      <Sfx name="pop" at={dbAt} volume={0.34} />
      <div style={{ position: "absolute", left: 120, top: 924, width: 1680, display: "flex", gap: 20, justifyContent: "center" }}>
        {["Runs in the background", "Pauses while you scroll or the phone is hot", "Nothing is uploaded"].map((text, i) => (
          <Rise key={text} at={dbAt + 0.5 + i * 0.25}>
            <Chip size={26}>{text}</Chip>
          </Rise>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const Lane: React.FC<{ y: number; at: number; tone: Tone; tag: string; title: string; line: string }> = ({ y, at, tone, tag, title, line }) => (
  <Box x={120} y={y} w={640} h={196} at={at} tone={tone} pad="24px 32px" sound="tick">
    <div style={{ fontSize: 24, fontWeight: 700, letterSpacing: 4, color: INK[tone] }}>{tag}</div>
    <div style={{ fontSize: 38, fontWeight: 800, color: "white", marginTop: 8 }}>{title}</div>
    <div style={{ fontSize: 28, color: SOFT, marginTop: 8, lineHeight: 1.25 }}>{line}</div>
  </Box>
);

const RankedRow: React.FC<{ y: number; at: number; label: string; photos: [string, boolean?][] }> = ({ y, at, label, photos }) => (
  <div style={{ position: "absolute", left: 850, top: y, fontFamily: FONT }}>
    <Rise at={at} distance={12}>
      <div style={{ fontSize: 24, color: DIM, letterSpacing: 1 }}>{label}</div>
    </Rise>
    <div style={{ display: "flex", gap: 22, marginTop: 18 }}>
      {photos.map(([src, best], i) => (
        <Rise key={src} at={at + 0.25 + i * 0.22}>
          <Thumb src={src} w={148} h={110} rank={i + 1} best={best} />
        </Rise>
      ))}
    </div>
    <Sfx name="pop" at={at + 0.25} volume={0.26} />
  </div>
);

export const HybridScene: React.FC = () => {
  const cue = cuesOf("hybrid");
  const words = cue("words", 3.6) - 0.2;
  const meaning = cue("meaning", 10.6) - 0.2;
  const fuse = cue("fuse", 14.4) - 0.2;
  const first = cue("first", 18) - 0.5;
  const result = useIn(first, 0.9);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Search" title="Two rankings, fused" />
      <div style={{ position: "absolute", left: 120, top: 204 }}>
        <Typed text="skiing, white hat, big smile" at={0.5} perSecond={26} sound />
      </div>
      <Lane y={392} at={words} tone="teal" tag="WORDS" title="Keyword match, BM25" line="your words against each photo’s description, tags and text" />
      <Lane y={624} at={meaning} tone="violet" tag="MEANING" title="Embedding similarity" line="your sentence’s MobileCLIP vector against every photo’s" />
      <Arrow from={[770, 490]} to={[838, 490]} at={words + 2.2} color={TEAL} />
      <Arrow from={[770, 722]} to={[838, 722]} at={meaning + 1.4} color={VIOLET} />
      <RankedRow y={404} at={words + 2.5} label="Ranked by words" photos={[["talk/ski.jpg", true], ["talk/ski2.jpg"], ["talk/hat.jpg"]]} />
      <RankedRow y={636} at={meaning + 1.7} label="Ranked by meaning" photos={[["talk/ski.jpg", true], ["talk/snowkid.jpg"], ["talk/ski2.jpg"]]} />
      <Arrow from={[1362, 490]} to={[1440, 566]} at={fuse - 0.3} />
      <Arrow from={[1362, 722]} to={[1440, 646]} at={fuse - 0.3} />
      <Box x={1448} y={486} w={352} h={236} at={fuse} pad="24px 26px" sound="tick">
        <div style={{ fontSize: 33, fontWeight: 800, color: "white", lineHeight: 1.15 }}>Reciprocal rank fusion</div>
        <div style={{ fontSize: 27, color: TEAL, marginTop: 16, fontFamily: MONO, whiteSpace: "nowrap" }}>Σ 1 / (60 + rank)</div>
        <div style={{ fontSize: 23, color: DIM, marginTop: 12, lineHeight: 1.25 }}>summed over both lists, for each photo</div>
      </Box>
      <div style={{ position: "absolute", left: 1448, top: 760, opacity: result, translate: `0px ${(1 - result) * 22}px`, display: "flex", alignItems: "center", gap: 22 }}>
        <Thumb src="talk/ski.jpg" w={176} h={124} rank={1} best />
        <div style={{ fontSize: 30, fontWeight: 700, color: TEAL, lineHeight: 1.2, width: 150 }}>Good on both: first</div>
      </div>
      <Sfx name="chime" at={first} volume={0.22} />
      <div style={{ position: "absolute", left: 120, top: 880, width: 1240 }}>
        <Rise at={first + 0.3}>
          <Chip size={27}>Only photos that really match are shown · about 30 ms a search</Chip>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

const QueryRow: React.FC<{ y: number; at: number; text: string; note: string; perSecond?: number; children: React.ReactNode }> = ({ y, at, text, note, perSecond = 26, children }) => (
  <>
    <div style={{ position: "absolute", left: 120, top: y - 44 }}>
      <Typed text={text} at={at} perSecond={perSecond} sound />
    </div>
    <Arrow from={[790, y + 48]} to={[880, y + 48]} at={at + 1.3} color={TEAL} />
    <div style={{ position: "absolute", left: 904, top: y + 14, fontFamily: FONT }}>
      <Rise at={at + 1.6}>
        <div style={{ display: "flex", gap: 16 }}>{children}</div>
      </Rise>
      <Rise at={at + 1.9}>
        <div style={{ fontSize: 28, color: SOFT, marginTop: 20 }}>{note}</div>
      </Rise>
      <Sfx name="pop" at={at + 1.6} volume={0.3} />
    </div>
  </>
);

export const QueryScene: React.FC = () => {
  const cue = cuesOf("query");
  // Each example is typed just before the narration names what happens to it.
  const at = (name: string, fallback: number) => Math.max(0.5, cue(name, fallback) - 1.5);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Query understanding" title="Before ranking, the query is read" />
      <QueryRow y={306} at={at("places", 3.4)} text="food in Tokyo in May" note="Places and dates become filters, not words to match">
        <Chip tone="teal" size={34} label="PLACE">Tokyo</Chip>
        <Chip tone="teal" size={34} label="TIME">May 2026</Chip>
        <Chip size={34} label="LOOKS LIKE">food</Chip>
      </QueryRow>
      <QueryRow y={530} at={at("typos", 6.4)} text="bicyle" note="Typos are corrected against the index’s own vocabulary">
        <Chip tone="teal" size={40}>bicycle</Chip>
      </QueryRow>
      <QueryRow y={754} at={at("chinese", 10.4)} text="女孩在河岸上奔跑跳跃" perSecond={9} note="Chinese is translated on the phone; a 4,585-concept dictionary backs it up">
        <Chip tone="teal" size={31}>The girl is running and jumping on the riverbank.</Chip>
      </QueryRow>
    </AbsoluteFill>
  );
};

export const AssistantScene: React.FC = () => {
  const cue = cuesOf("assistant");
  const model = cue("model", 2.8) - 0.2;
  const tools = cue("tools", 4.4) - 0.2;
  const index = cue("index", 5.6);
  const back = cue("back", 6.8);
  const answerAt = cue("answer", 8) + 0.5;
  const answer = useIn(answerAt, 0.8);
  const indexIn = useIn(index, 0.7);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Assistant" title="A language model that calls tools" />
      <Box x={120} y={318} w={480} h={150} at={0.6} tone="violet" pad="22px 30px" sound="pop">
        <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: 3, color: VIOLET }}>YOU ASK</div>
        <div style={{ fontSize: 34, color: "white", marginTop: 10, lineHeight: 1.2 }}>“How much did I spend at Muji?”</div>
      </Box>
      <Arrow from={[610, 393]} to={[708, 393]} at={model - 0.3} />
      <Box x={716} y={278} w={470} h={270} at={model} pad="28px 30px">
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <Icon name="chip" size={50} />
          <div style={{ fontSize: 40, fontWeight: 800, color: "white" }}>Language model</div>
        </div>
        <div style={{ marginTop: 22 }}><Chip tone="teal" size={26}>Apple Intelligence, on the iPhone</Chip></div>
        <div style={{ marginTop: 14 }}><Chip size={26}>or a cloud model you choose</Chip></div>
      </Box>
      <Arrow from={[1196, 360]} to={[1310, 360]} at={tools} color={TEAL} label="tool call" />
      <Arrow from={[1310, 466]} to={[1196, 466]} at={back} color={TEAL} label="text only" labelDy={38} />
      <Box x={1318} y={250} w={482} h={330} at={tools - 0.2} pad="26px 34px">
        <div style={{ fontSize: 36, fontWeight: 800, color: "white" }}>Tools</div>
        <div style={{ fontFamily: MONO, fontSize: 28, color: SOFT, marginTop: 12, lineHeight: 1.55 }}>
          {["find_photos", "list_places", "list_collections", "show_photos", "propose_album"].map((tool) => (
            <div key={tool}>{tool}</div>
          ))}
        </div>
      </Box>
      <Sfx name="tick" at={tools} volume={0.32} />
      <Sfx name="tick" at={back} volume={0.32} />
      <Arrow from={[1560, 590]} to={[1560, 678]} at={index - 0.2} />
      <div style={{ position: "absolute", left: 1410, top: 690, width: 300, textAlign: "center", opacity: indexIn }}>
        <Icon name="db" size={130} />
        <div style={{ fontSize: 32, fontWeight: 800, color: "white" }}>Local index</div>
      </div>
      <Arrow from={[850, 558]} to={[640, 690]} at={answerAt - 0.4} />
      <div
        style={{
          position: "absolute", left: 120, top: 640, width: 560, height: 250, boxSizing: "border-box", padding: "24px 28px", borderRadius: 28,
          background: FILL.teal, border: `2px solid ${TEAL}`, display: "flex", gap: 24, alignItems: "center",
          opacity: answer, translate: `0px ${(1 - answer) * 24}px`, boxShadow: `0 0 ${60 * answer}px rgba(94,230,217,0.2)`,
        }}
      >
        <Thumb src="talk/receipt_muji.jpg" w={158} h={182} />
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: 3, color: TEAL }}>THE ANSWER</div>
          <div style={{ fontSize: 50, fontWeight: 800, color: "white", marginTop: 6 }}>HK$702.00</div>
          <div style={{ fontSize: 25, color: SOFT, marginTop: 6, lineHeight: 1.25 }}>read from the text of the receipt</div>
        </div>
      </div>
      <Sfx name="chime" at={answerAt} volume={0.22} />
      <div style={{ position: "absolute", left: 730, top: 716 }}>
        <Rise at={cue("text", 10.6)}>
          <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 31, color: "white" }}>
            <Icon name="lock" size={42} /> The model sees text, never the images
          </div>
        </Rise>
        <Rise at={cue("tap", 13)}>
          <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 31, color: "white", marginTop: 26 }}>
            <Icon name="check" size={42} /> Changes to your library wait for your tap
          </div>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

const Stage: React.FC<{ x: number; y: number; w: number; h?: number; at: number; tone?: Tone; title: string; line?: string; children?: React.ReactNode }> = ({
  x, y, w, h = 190, at, tone, title, line, children,
}) => (
  <Box x={x} y={y} w={w} h={h} at={at} tone={tone} pad="22px 28px" sound="tick">
    {children}
    <div style={{ fontSize: 32, fontWeight: 700, color: "white", lineHeight: 1.2 }}>{title}</div>
    {line ? <div style={{ fontSize: 26, color: SOFT, marginTop: 8, lineHeight: 1.25 }}>{line}</div> : null}
  </Box>
);

const RowLabel: React.FC<{ y: number; at: number; icon: string; text: string }> = ({ y, at, icon, text }) => (
  <div style={{ position: "absolute", left: 120, top: y }}>
    <Rise at={at}>
      <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 28, fontWeight: 700, letterSpacing: 4, color: TEAL }}>
        <Icon name={icon} size={40} /> {text}
      </div>
    </Rise>
  </div>
);

export const NotesEditsScene: React.FC = () => {
  const cue = cuesOf("notes");
  const group = cue("group", 2.8);
  const text = cue("text", 6.4);
  const out = cue("out", 9.4);
  const edit = cue("edit", 13);
  const phone = cue("phone", 14.2);
  const ai = cue("ai", 15.6);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Study and edit" title="The same index, two more uses" />
      <RowLabel y={268} at={0.5} icon="book" text="LECTURE NOTES" />
      <Stage x={120} y={326} w={330} at={0.9} title="Slide photos">
        <div style={{ display: "flex", marginBottom: 14 }}>
          {[1, 2, 3].map((n) => (
            <Img key={n} src={staticFile(`slides/s${n}.jpg`)} style={{ width: 104, height: 78, objectFit: "cover", borderRadius: 8, border: "2px solid rgba(255,255,255,0.8)", marginLeft: n === 1 ? 0 : -22, rotate: `${(n - 2) * 3}deg` }} />
          ))}
        </div>
      </Stage>
      <Arrow from={[460, 421]} to={[512, 421]} at={group - 0.3} />
      <Stage x={520} y={326} w={370} at={group} title="Grouped into lectures" line="photos taken less than 30 minutes apart" />
      <Arrow from={[900, 421]} to={[952, 421]} at={text - 0.3} />
      <Stage x={960} y={326} w={370} at={text} title="Only the recognised text" line="goes to the language model, never the photos" />
      <Arrow from={[1340, 421]} to={[1392, 421]} at={out - 0.3} />
      <Stage x={1400} y={326} w={400} at={out} tone="teal" title="Summary, key points, flashcards" line="as structured output, with slide numbers" />

      <RowLabel y={590} at={edit - 0.5} icon="sliders" text="EDIT BY REQUEST" />
      <Stage x={120} y={648} w={460} h={170} at={edit - 0.1} tone="violet" title="“warmer, and blur the background”" line="typed by you" />
      <Arrow from={[590, 733]} to={[642, 733]} at={phone - 0.3} />
      <Stage x={650} y={648} w={470} h={170} at={phone} title="Read on the phone" line="word rules, plus the on-device model" />
      <Arrow from={[1130, 733]} to={[1182, 733]} at={phone + 0.5} />
      <Stage x={1190} y={648} w={610} h={170} at={phone + 0.8} tone="teal" title="Applied with Core Image and Vision" line="free, on the iPhone, and can be reverted" />
      <Arrow from={[885, 826]} to={[885, 878]} at={ai - 0.2} color={PINK} dashed />
      <div style={{ position: "absolute", left: 650, top: 886 }}>
        <Rise at={ai}>
          <Chip tone="pink" size={27}>“add a hot air balloon in the sky” → an AI image service, only after you confirm</Chip>
        </Rise>
        <Sfx name="pop" at={ai} volume={0.3} />
      </div>
    </AbsoluteFill>
  );
};

// MARK: Implementation

const MODULES = [
  ["photo", "Library and viewer", "PhotoKit, UIKit collection views"],
  ["text", "Indexer", "Apple Vision: text and labels"],
  ["bars", "Embeddings", "MobileCLIP S0, Core ML"],
  ["pen", "Descriptions", "Apple Intelligence, or SmolVLM2 on MLX"],
  ["db", "Local index", "SQLite with full-text search"],
  ["search", "Search engine", "BM25 + embeddings, fused"],
  ["chat", "Assistant", "one interface: on-device or cloud"],
  ["book", "Study and editor", "structured notes, Core Image"],
];

const Fact: React.FC<{ at: number; big: React.ReactNode; label: string }> = ({ at, big, label }) => (
  <Rise at={at}>
    <div style={{ marginBottom: 34 }}>
      <div style={{ color: TEAL, fontSize: 86, fontWeight: 800, fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>{big}</div>
      <div style={{ color: SOFT, fontSize: 31, marginTop: 8, lineHeight: 1.25 }}>{label}</div>
    </div>
  </Rise>
);

export const BuiltScene: React.FC = () => {
  const cue = cuesOf("built");
  const lines = cue("lines", 5.4) - 0.3;
  const modules = cue("models", 8.6) - 2.2;
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="What we built" title="A native iOS app, in Swift and SwiftUI" />
      <div style={{ position: "absolute", left: 120, top: 300, width: 540 }}>
        <Fact at={lines} big={<>≈<Count to={14000} at={lines} seconds={1.6} /></>} label="lines of Swift, in 60 files" />
        <Fact at={lines + 1.3} big="iOS 26+" label="built with Xcode, in Swift 6" />
        <Fact at={lines + 2.4} big="18 Pro Max" label="the iPhone simulator every demo here is recorded in" />
      </div>
      <Sfx name="rise" at={lines} volume={0.2} />
      {MODULES.map(([icon, name, tech], i) => (
        <Box key={name} x={700 + (i % 2) * 560} y={286 + Math.floor(i / 2) * 166} w={540} h={146} at={modules + i * 0.5} pad="0 28px" sound="tick">
          <div style={{ display: "flex", alignItems: "center", gap: 22, height: "100%" }}>
            <Icon name={icon} size={56} />
            <div>
              <div style={{ fontSize: 34, fontWeight: 700, color: "white" }}>{name}</div>
              <div style={{ fontSize: 25, color: SOFT, marginTop: 6 }}>{tech}</div>
            </div>
          </div>
        </Box>
      ))}
    </AbsoluteFill>
  );
};

export const FindTalk: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="ski" />
    <Side top={230}>
      <Heading eyebrow="Scenario 1, solved" title="Type what you remember" />
      <Typed text="skiing, white hat, big smile" at={1.5} sound />
      <Steps
        sound
        items={[
          { at: 3.6, text: "The matching photo appears at once" },
          { at: 5.5, text: "Then the answer: Zermatt, Switzerland" },
          { at: 8.6, text: "Opened: 13 January 2026" },
        ]}
      />
    </Side>
    <Sfx name="chime" at={8.4} volume={0.22} />
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

export const AskTalk: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="ask-lecture" />
    <Side top={230}>
      <Heading eyebrow="Scenario 2, solved" title="Ask for the lecture back" />
      <Typed text="Summarise the slides from today’s lecture" at={0.2} perSecond={34} sound />
      <Steps
        sound
        items={[
          { at: 2.3, text: "Finds today’s slides among everything else" },
          { at: 4.3, text: "Reads them and sums them up" },
        ]}
      />
    </Side>
    <Sfx name="chime" at={5.0} volume={0.2} />
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

export const NotesTalk: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="notes-short" />
    <Side top={230}>
      <Heading eyebrow="Study" title="Slides become notes" />
      <Steps
        top={56}
        sound
        items={[
          { at: 0.6, text: "One tap: Make notes" },
          { at: 2.1, text: "A summary, written on the phone" },
          { at: 5.4, text: "Key points, each with its slide number" },
          { at: 9.4, text: "Flashcards to revise before the quiz" },
        ]}
      />
    </Side>
    <Sfx name="flip" at={10.2} volume={0.3} />
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

export const MujiTalk: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="muji" />
    <Side>
      <Heading eyebrow="Ask" title="Answers from what’s in the photo" size={78} />
      <Typed text="How much did I spend at Muji?" at={0.2} perSecond={34} sound />
      <div>
        <Callout at={2.9} label="Read from the receipt" value="HK$702.00" />
      </div>
    </Side>
    <Sfx name="chime" at={2.9} volume={0.22} />
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

export const ChineseScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="zh" />
    <Side>
      <Heading eyebrow="Ask" title="The same question, in Chinese" size={78} />
      <Typed text="我在无印良品花了多少钱？" at={0.2} perSecond={16} sound />
      <div>
        <Callout at={2.2} label="Same English receipt" value="HK$702.00" />
      </div>
    </Side>
    <Sfx name="chime" at={2.2} volume={0.22} />
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

/** The AI edit. `steps` follow the recording: when the request is read, when the card asks, and what comes after. */
export const EditTalk: React.FC<{ clip?: string; typedAt?: number; steps?: { at: number; text: string }[]; doneAt?: number }> = ({
  clip = "aiedit", typedAt = 2.6,
  steps = [
    { at: 4.6, text: "Read on the phone first" },
    { at: 6.3, text: "Too big for the phone, so Phophy asks before sending" },
    { at: 8.4, text: "Sent to the AI image service you chose" },
    { at: 12.6, text: "About 40 seconds later: the balloon is in the sky" },
  ],
  doneAt = 12.65,
}) => (
  <AbsoluteFill>
    <Phone clip={clip} />
    <Side top={210}>
      <Heading eyebrow="Edit" title="Describe the change" />
      <Typed text="add a red hot air balloon in the sky" at={typedAt} perSecond={30} icon="✎" sound />
      <Steps sound items={steps} />
    </Side>
    {doneAt ? <Sfx name="chime" at={doneAt} volume={0.22} /> : null}
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

export const CollectionsTalk: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="collections-short" />
    <Side>
      <Heading eyebrow="Collections" title="Sorted for you" />
      <Steps
        top={56}
        sound
        items={[
          { at: 0.8, text: "Slides, receipts, documents, people, pets" },
          { at: 7.4, text: "Near-identical shots, with one to keep" },
        ]}
      />
    </Side>
    <Footnote text={SIMULATOR} />
  </AbsoluteFill>
);

// MARK: Key results

export const ResultsTalk: React.FC = () => {
  const cue = cuesOf("results-search");
  const at = [cue("zh", 6.6), cue("typo", 10), cue("obj", 12.4), cue("long", 14.8) + 0.4].map((s) => s - 0.2);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <div style={{ position: "absolute", left: 140, top: 80 }}>
        <Words text="Search, measured" at={0.1} style={{ color: "white", fontSize: 76, fontWeight: 800 }} />
      </div>
      <Rise at={1.6}>
        <div style={{ position: "absolute", left: 142, top: 185, color: SOFT, fontSize: 36 }}>Flickr30k benchmark · 1,000 photos · 362 searches</div>
      </Rise>
      <Rise at={3.6}>
        <div style={{ position: "absolute", left: 840, top: 260, display: "flex", gap: 40, fontSize: 30 }}>
          <span style={{ color: "rgba(170,170,210,0.95)" }}>■ first version</span>
          <span style={{ color: TEAL }}>■ Phophy now</span>
        </div>
      </Rise>
      <Bar label="Chinese searches, top-10 correct" before={0.02} after={0.51} at={at[0]} y={340} />
      <Bar label="Misspelled searches, top-10 correct" before={0.13} after={0.59} at={at[1]} y={510} />
      <Bar label="Objects found in the top 50" before={0.51} after={0.89} at={at[2]} y={680} />
      <Bar label="Long descriptions, right photo first" before={0.76} after={0.76} at={at[3]} y={850} />
      {at.map((s) => (
        <Sfx key={s} name="rise" at={s} volume={0.2} />
      ))}
    </AbsoluteFill>
  );
};

const HBar: React.FC<{ at: number; label: string; value: number; tone?: Tone; note?: string; ghost?: boolean; sound?: boolean }> = ({
  at, label, value, tone = "plain", note, ghost, sound,
}) => {
  const p = useIn(at, 1.3);
  const show = useIn(at, 0.5);
  const w = 400;
  const color = tone === "teal" ? TEAL : tone === "violet" ? VIOLET : "rgba(170,170,210,0.9)";
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 20, marginTop: 30, opacity: show }}>
      <div style={{ width: 250, fontSize: 28, color: "white", lineHeight: 1.2 }}>
        {label}
        {note ? <div style={{ fontSize: 21, color: DIM, marginTop: 2 }}>{note}</div> : null}
      </div>
      <div style={{ width: w, height: 30, borderRadius: 15, background: "rgba(255,255,255,0.08)" }}>
        <div
          style={{
            width: Math.max(10, w * value * p), height: 30, borderRadius: 15, boxSizing: "border-box",
            background: ghost ? "transparent" : color, border: ghost ? `2.5px dashed ${color}` : undefined,
          }}
        />
      </div>
      <div style={{ width: 86, fontSize: 36, fontWeight: 800, color, fontVariantNumeric: "tabular-nums" }}>{Math.round(value * p * 100)}%</div>
      {sound ? <Sfx name="rise" at={at} volume={0.2} /> : null}
    </div>
  );
};

export const LanguageScene: React.FC = () => {
  const cue = cuesOf("results-language");
  const dict = cue("dict", 6) - 0.4;
  const trans = cue("trans", 7.2) - 0.5;
  const human = cue("human", 9);
  const para = cue("para", 11.4);
  const vec = cue("vec", 13) - 0.4;
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Language" title="Chinese and paraphrased searches" />
      <Box x={120} y={286} w={830} h={590} at={0.5} pad="32px 38px">
        <div style={{ fontSize: 38, fontWeight: 800, color: "white" }}>Chinese sentences</div>
        <div style={{ fontSize: 26, color: SOFT, marginTop: 6 }}>right photo in the top 5 · 30 searches</div>
        <HBar at={1.4} label="As typed" value={0} />
        <HBar at={dict} label="Concept dictionary" value={0.6} sound />
        <HBar at={trans} label="Translated on the phone" value={0.867} tone="teal" sound />
        <HBar at={human} label="Human English" note="upper bound" value={0.867} ghost />
        <Rise at={human + 0.8}>
          <div style={{ marginTop: 40, fontSize: 26, color: SOFT, lineHeight: 1.4 }}>Captions from the Flickr30k benchmark, translated into Chinese by hand, each with one right photo among 1,000.</div>
        </Rise>
      </Box>
      <Sfx name="chime" at={trans + 1.2} volume={0.2} />
      <Box x={980} y={286} w={820} h={590} at={para - 0.4} pad="32px 38px">
        <div style={{ fontSize: 38, fontWeight: 800, color: "white" }}>Paraphrased searches</div>
        <div style={{ fontSize: 26, color: SOFT, marginTop: 6 }}>slides and documents, found in the top 10 · 50 searches</div>
        <HBar at={para + 0.5} label="Keywords" note="the app today" value={0.5} />
        <HBar at={vec} label="+ sentence vectors" note="of the text in photos" value={0.74} tone="teal" sound />
        <Rise at={vec + 1.6}>
          <div style={{ marginTop: 44, fontSize: 26, color: SOFT, lineHeight: 1.4 }}>
            “notes about TCP handshakes”
            <span style={{ color: TEAL }}> → </span>
            the slide titled “The Three-Way Handshake”
          </div>
          <div style={{ marginTop: 22 }}><Chip tone="pink" size={24}>An experiment: not in the app yet</Chip></div>
        </Rise>
      </Box>
    </AbsoluteFill>
  );
};

/** The assistant test on the final build: how many of the 20 tasks passed in each of the runs. */
export const AGENT = {
  low: 14, high: 17, always: 14, some: 4, never: 2, runs: "three runs",
  chips: ["about 7 s a task", "1.7 tool calls", "no cost"],
  works: ["A receipt total, the rent, a Wi-Fi password", "Deadlines on lecture slides", "Finding a letter or a whiteboard", "Building an album of a trip", "Four of the six tasks asked in Chinese"],
  fails: ["A train’s departure time, from a booking screenshot", "A booking mentioned in a chat", "A boarding gate, and the totals on two receipts"],
};

export const AgentScene: React.FC = () => {
  const t = useTime();
  const cue = cuesOf("results-assistant");
  const count = cue("count", 4.6) - 0.4;
  const chipsAt = cue("time", 8.2);
  const fails = cue("fails", 11) - 0.2;
  const kinds = [...Array(AGENT.always).fill("pass"), ...Array(AGENT.some).fill("some"), ...Array(AGENT.never).fill("fail")];
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Assistant" title="Can it finish real tasks?" />
      <div style={{ position: "absolute", left: 120, top: 286, width: 800 }}>
        <Rise at={count}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 24 }}>
            <div style={{ fontSize: 168, fontWeight: 800, color: TEAL, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>
              {AGENT.low === AGENT.high ? <Count to={AGENT.high} at={count} /> : <><Count to={AGENT.low} at={count} />–<Count to={AGENT.high} at={count} /></>}
            </div>
            <div style={{ fontSize: 46, color: "white", fontWeight: 700 }}>of 20 tasks</div>
          </div>
          <div style={{ fontSize: 28, color: SOFT, marginTop: 14 }}>Apple’s on-device model · {AGENT.runs} · a library with known answers</div>
        </Rise>
        <Sfx name="rise" at={count} volume={0.2} />
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, width: 620, marginTop: 36 }}>
          {kinds.map((kind, i) => {
            const p = interpolate(t, [count + 1.4 + i * 0.07, count + 1.8 + i * 0.07], [0, 1], { ...clamp, easing: OUT });
            const color = kind === "fail" ? PINK : TEAL;
            return (
              <div
                key={i}
                style={{
                  width: 44, height: 44, borderRadius: 22, boxSizing: "border-box", scale: String(p), opacity: p,
                  background: kind === "some" ? "transparent" : color, border: `4px solid ${color}`,
                }}
              />
            );
          })}
        </div>
        {[0, 5, 10, 15].map((i) => (
          <Sfx key={i} name="tick" at={count + 1.5 + i * 0.07} volume={0.26} />
        ))}
        <Rise at={count + 3}>
          <div style={{ display: "flex", gap: 30, marginTop: 22, fontSize: 24, color: SOFT }}>
            <span><span style={{ color: TEAL }}>●</span> every run</span>
            <span><span style={{ color: TEAL }}>○</span> some runs</span>
            <span><span style={{ color: PINK }}>●</span> never</span>
          </div>
        </Rise>
        <div style={{ display: "flex", gap: 18, marginTop: 40 }}>
          {AGENT.chips.map((text, i) => (
            <Rise key={text} at={chipsAt + i * 0.6}>
              <Chip size={29}>{text}</Chip>
            </Rise>
          ))}
        </div>
      </div>
      <Box x={980} y={286} w={820} h={332} at={chipsAt + 1.4} tone="teal" pad="26px 34px" sound="pop">
        <div style={{ fontSize: 24, fontWeight: 700, letterSpacing: 3, color: TEAL }}>WORKS</div>
        {AGENT.works.map((text) => (
          <div key={text} style={{ fontSize: 31, color: "white", marginTop: 13 }}>{text}</div>
        ))}
      </Box>
      <Box x={980} y={644} w={820} h={232} at={fails} tone="pink" pad="26px 34px" sound="pop">
        <div style={{ fontSize: 24, fontWeight: 700, letterSpacing: 3, color: PINK }}>FAILS IN SOME OR ALL RUNS</div>
        {AGENT.fails.map((text) => (
          <div key={text} style={{ fontSize: 31, color: "white", marginTop: 13 }}>{text}</div>
        ))}
      </Box>
    </AbsoluteFill>
  );
};

export const NextScene: React.FC = () => {
  const cue = cuesOf("next");
  const rows = [
    ["pen", "A stronger reader for documents", "the small on-device model misreads some tickets and receipts", "r1"],
    ["bars", "Text vectors inside the app", "in our experiment they found 74% of paraphrased searches, up from 50%", "r2"],
    ["grid", "The remaining measurements", "cloud models and their cost, categories, duplicates, notes, speed at scale", "r3"],
  ];
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Top eyebrow="Limits and next steps" title="What’s next" />
      {rows.map(([icon, title, line, name], i) => (
        <Box key={title} x={120} y={300 + i * 200} w={1680} h={170} at={cue(name, 1.4 + i * 2) - 0.2} pad="0 40px" sound="tick">
          <div style={{ display: "flex", alignItems: "center", gap: 34, height: "100%" }}>
            <Icon name={icon} size={72} />
            <div>
              <div style={{ fontSize: 46, fontWeight: 800, color: "white" }}>{title}</div>
              <div style={{ fontSize: 31, color: SOFT, marginTop: 8 }}>{line}</div>
            </div>
          </div>
        </Box>
      ))}
    </AbsoluteFill>
  );
};

// MARK: Closing

export const ThanksTalk: React.FC = () => (
  <>
    <ThanksScene />
    <Sfx name="chime" at={0.5} volume={0.2} />
  </>
);
