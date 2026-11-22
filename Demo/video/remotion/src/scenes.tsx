import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Count, FONT, Phone, Rise, SOFT, Shot, SideText, TEAL, TypedField, useIn } from "./ui";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Frames a TypedField needs before its text is complete. */
const typed = (text: string) => Math.ceil(Array.from(text).length * 1.6) + 10;

const Footnote: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 300,
      bottom: 22,
      width: 456,
      textAlign: "center",
      fontFamily: FONT,
      fontSize: 20,
      color: "rgba(226,232,255,0.55)",
    }}
  >
    Real screens from Phophy, iOS 27 simulator
  </div>
);

// MARK: 1 · Title

const PhotoTile: React.FC<{ n: number; i: number; frame: number }> = ({ n, i, frame }) => {
  const col = i % 6;
  const row = Math.floor(i / 6);
  const p = useIn(i * 2, 30);
  const drift = frame * 0.35 * (row % 2 === 0 ? 1 : -1);
  return (
    <Img
      src={staticFile(`photos/p${n}.jpg`)}
      style={{
        position: "absolute",
        width: 300,
        height: 300,
        borderRadius: 36,
        objectFit: "cover",
        left: -80 + col * 340 + drift + (row % 2) * 170,
        top: 40 + row * 340,
        opacity: p * 0.42,
        rotate: `${(i % 3) - 1}deg`,
        scale: String(interpolate(p, [0, 1], [0.8, 1])),
        boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
      }}
    />
  );
};

export const TitleScene: React.FC = () => {
  const frame = useCurrentFrame();
  const photos = Array.from({ length: 18 }, (_, i) => i + 1);
  return (
    <AbsoluteFill>
      {photos.map((n, i) => (
        <PhotoTile key={n} n={n} i={i} frame={frame} />
      ))}
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 50%, rgba(20,14,60,0.75), rgba(20,14,60,0.35) 70%)" }} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, textAlign: "center" }}>
        <Rise at={10} distance={40}>
          <div style={{ fontSize: 190, fontWeight: 800, color: "white", letterSpacing: -4 }}>Phophy</div>
        </Rise>
        <Rise at={24}>
          <div style={{ fontSize: 54, color: SOFT, marginTop: 6 }}>Find anything in your photos, on your iPhone</div>
        </Rise>
        <Rise at={44}>
          <div style={{ fontSize: 34, color: TEAL, marginTop: 70, fontWeight: 700, letterSpacing: 3 }}>TEAM 26</div>
          <div style={{ fontSize: 34, color: SOFT, marginTop: 14 }}>
            Su Chuanzhou · Yin Fengling · Qin Mengmeng · Wang Zhengyao
          </div>
        </Rise>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// MARK: 2 · Problem

export const ProblemScene: React.FC = () => {
  const rows = [
    ["🧾", "Receipts, slides, screenshots and trips, all mixed together"],
    ["⏳", "Finding one photo means minutes of scrolling"],
    ["☁️", "Sending everything to a cloud AI costs money, and gives your photos away"],
  ];
  return (
    <AbsoluteFill style={{ fontFamily: FONT, padding: "150px 160px" }}>
      <Rise at={4}>
        <div style={{ color: TEAL, fontSize: 34, fontWeight: 700, letterSpacing: 4 }}>THE PROBLEM</div>
      </Rise>
      <Rise at={10}>
        <div style={{ color: "white", fontSize: 150, fontWeight: 800, marginTop: 10, fontVariantNumeric: "tabular-nums" }}>
          <Count to={16080} at={14} frames={60} /> <span style={{ fontSize: 64, color: SOFT, fontWeight: 600 }}>photos on one phone</span>
        </div>
      </Rise>
      <div style={{ marginTop: 50 }}>
        {rows.map(([icon, text], i) => (
          <Rise key={text} at={70 + i * 55}>
            <div style={{ display: "flex", alignItems: "center", gap: 34, marginTop: 30 }}>
              <div style={{ fontSize: 60, width: 90, textAlign: "center" }}>{icon}</div>
              <div style={{ fontSize: 52, color: "white" }}>{text}</div>
            </div>
          </Rise>
        ))}
      </div>
    </AbsoluteFill>
  );
};

// MARK: 3 · How it works

const Box: React.FC<{ x: number; y: number; w: number; h: number; at: number; title: string; sub?: string; tone?: "light" | "index" | "out" }> = ({
  x, y, w, h, at, title, sub, tone = "light",
}) => {
  const p = useIn(at, 18);
  const bg = tone === "index" ? "rgba(94,230,217,0.18)" : tone === "out" ? "rgba(124,92,255,0.32)" : "rgba(255,255,255,0.10)";
  const border = tone === "index" ? TEAL : "rgba(255,255,255,0.28)";
  return (
    <div
      style={{
        position: "absolute", left: x, top: y, width: w, height: h, borderRadius: 26, background: bg,
        border: `2px solid ${border}`, display: "flex", flexDirection: "column", justifyContent: "center",
        alignItems: "center", fontFamily: FONT, opacity: p, scale: String(interpolate(p, [0, 1], [0.9, 1])),
        boxShadow: "0 18px 50px rgba(0,0,0,0.25)",
      }}
    >
      <div style={{ color: "white", fontSize: 36, fontWeight: 700 }}>{title}</div>
      {sub ? <div style={{ color: SOFT, fontSize: 26, marginTop: 6 }}>{sub}</div> : null}
    </div>
  );
};

const Line: React.FC<{ x1: number; y1: number; x2: number; y2: number; at: number; dashed?: boolean }> = ({ x1, y1, x2, y2, at, dashed }) => {
  const p = useIn(at, 16);
  const len = Math.hypot(x2 - x1, y2 - y1);
  return (
    <svg style={{ position: "absolute", left: 0, top: 0, width: 1920, height: 1080, overflow: "visible" }}>
      <line
        x1={x1} y1={y1} x2={x1 + (x2 - x1) * p} y2={y1 + (y2 - y1) * p}
        stroke={dashed ? "rgba(255,200,120,0.8)" : "rgba(226,232,255,0.55)"} strokeWidth={4}
        strokeDasharray={dashed ? "12 10" : undefined} strokeLinecap="round"
        opacity={len > 0 ? 1 : 0}
      />
    </svg>
  );
};

export const HowScene: React.FC = () => {
  const inputs = [
    ["Text in the photo", "OCR"],
    ["What it shows", "labels and tags"],
    ["How it looks", "MobileCLIP embedding"],
    ["A short description", "on-device AI"],
  ];
  const outputs = ["Search", "Collections", "Study", "Assistant"];
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <Rise at={2}>
        <div style={{ position: "absolute", left: 120, top: 70, color: "white", fontSize: 72, fontWeight: 800 }}>How it works</div>
      </Rise>
      <Rise at={8}>
        <div style={{ position: "absolute", left: 122, top: 165, color: TEAL, fontSize: 30, fontWeight: 700, letterSpacing: 3 }}>
          ON THE IPHONE · PRIVATE · FREE
        </div>
      </Rise>
      {/* The photo */}
      <Rise at={10}>
        <Img src={staticFile("photos/p14.jpg")} style={{ position: "absolute", left: 120, top: 430, width: 220, height: 220, borderRadius: 28, boxShadow: "0 20px 60px rgba(0,0,0,0.4)" }} />
      </Rise>
      {inputs.map(([title, sub], i) => (
        <React.Fragment key={title}>
          <Line x1={340} y1={540} x2={470} y2={300 + i * 160} at={30 + i * 10} />
          <Box x={470} y={250 + i * 160} w={420} h={110} at={34 + i * 10} title={title} sub={sub} />
          <Line x1={890} y1={305 + i * 160} x2={1010} y2={540} at={90 + i * 6} />
        </React.Fragment>
      ))}
      <Box x={1010} y={440} w={330} h={200} at={110} title="Local index" sub="SQLite, on the phone" tone="index" />
      {outputs.map((title, i) => (
        <React.Fragment key={title}>
          <Line x1={1340} y1={540} x2={1470} y2={300 + i * 160} at={150 + i * 8} />
          <Box x={1470} y={255 + i * 160} w={330} h={100} at={155 + i * 8} title={title} tone="out" />
        </React.Fragment>
      ))}
      <Rise at={240}>
        <div style={{ position: "absolute", left: 470, top: 925, fontSize: 30, color: "rgba(255,210,150,0.95)" }}>
          ☁︎ Cloud models only if you choose one, after a clear warning
        </div>
      </Rise>
    </AbsoluteFill>
  );
};

// MARK: Phone scenes

type Query = { text: string; shot: string; label?: string };

/** Search queries typed one after another, each followed by its results. */
const searchTimeline = (queries: Query[], first: number, each: number) => {
  const shots: Shot[] = [];
  const fields = queries.map((q, i) => {
    const at = first + i * each;
    shots.push({ src: q.shot, at: at + typed(q.text) });
    return { ...q, at, until: i < queries.length - 1 ? first + (i + 1) * each - 8 : undefined };
  });
  return { shots, fields };
};

export const LibraryScene: React.FC = () => (
  <AbsoluteFill>
    <Phone shots={[
      { src: "library", at: 0 },
      { src: "info", at: 95, zoom: { x: 120, y: 2040, scale: 1.12, at: 125 } },
    ]} />
    <SideText eyebrow="Library" title="Every photo, read once" lines={["Where it was taken", "A description written on the phone", "Every word on the receipt"]} />
    <Footnote />
  </AbsoluteFill>
);

const SearchScene: React.FC<{ eyebrow: string; title: string; lines: string[]; queries: Query[]; each: number }> = ({ eyebrow, title, lines, queries, each }) => {
  const { shots, fields } = searchTimeline(queries, 18, each);
  return (
    <AbsoluteFill>
      <Phone shots={[{ src: "library", at: 0 }, ...shots]} />
      <SideText eyebrow={eyebrow} title={title} lines={lines} />
      {fields.map((f) => (
        <React.Fragment key={f.text}>
          <TypedField text={f.text} at={f.at} until={f.until} x={860} y={760} />
          {f.label ? <QueryLabel text={f.label} at={f.at + typed(f.text)} until={f.until} /> : null}
        </React.Fragment>
      ))}
      <Footnote />
    </AbsoluteFill>
  );
};

const QueryLabel: React.FC<{ text: string; at: number; until?: number }> = ({ text, at, until }) => {
  const frame = useCurrentFrame();
  const p = useIn(at, 12);
  const leave = until === undefined ? 0 : interpolate(frame, [until, until + 10], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", left: 866, top: 880, fontFamily: FONT, fontSize: 32, color: TEAL, opacity: p * (1 - leave) }}>
      {text}
    </div>
  );
};

export const SearchMeaningScene: React.FC = () => (
  <SearchScene
    eyebrow="Search"
    title="Search by meaning"
    lines={["About 20 ms per search"]}
    each={92}
    queries={[
      { text: "dog on the beach", shot: "q-dog-beach", label: "a scene" },
      { text: "Tokyo", shot: "q-tokyo", label: "a place" },
      { text: "bicyle", shot: "q-bicyle", label: "a typo, still bicycles" },
      { text: "狗", shot: "q-dog-zh", label: "Chinese for “dog”" },
    ]}
  />
);

export const SearchTextScene: React.FC = () => (
  <SearchScene
    eyebrow="Search"
    title="Words in photos"
    lines={["and photos described in a sentence"]}
    each={100}
    queries={[
      { text: "G1234", shot: "q-g1234", label: "a train number in a screenshot" },
      { text: "receipt from Muji", shot: "q-muji", label: "a shop on a receipt" },
      { text: "whiteboard with the network diagram", shot: "q-whiteboard", label: "a sentence" },
    ]}
  />
);

export const CollectionsScene: React.FC = () => (
  <AbsoluteFill>
    <Phone shots={[{ src: "collections", at: 0 }, { src: "similar", at: 190 }]} />
    <SideText eyebrow="Collections" title="Sorted for you" lines={["Slides, receipts, documents, pets…", "Near-identical shots found,", "with one to keep suggested"]} />
    <Footnote />
  </AbsoluteFill>
);

export const StudyScene: React.FC = () => (
  <AbsoluteFill>
    <Phone shots={[
      { src: "study-list", at: 0 },
      { src: "study-make", at: 70 },
      { src: "study-writing", at: 120 },
      { src: "study-keypoints", at: 190 },
      { src: "flashcard", at: 330 },
    ]} />
    <SideText eyebrow="Study" title="Slides become notes" lines={["Grouped by lecture", "Summary and key points", "Flashcards to revise", "From the slide text only"]} />
    <Footnote />
  </AbsoluteFill>
);

const AskScene: React.FC<{ question: string; shots: Shot[]; title: string; lines: string[]; answer: string; answerAt: number }> = ({
  question, shots, title, lines, answer, answerAt,
}) => (
  <AbsoluteFill>
    <Phone shots={[{ src: "library", at: 0 }, ...shots]} />
    <SideText eyebrow="Ask" title={title} lines={lines} />
    <TypedField text={question} at={14} x={860} y={700} icon="ask" />
    <Answer text={answer} at={answerAt} />
    <Footnote />
  </AbsoluteFill>
);

/** The answer the app gave, pulled out large beside the phone. */
const Answer: React.FC<{ text: string; at: number }> = ({ text, at }) => {
  const p = useIn(at, 20);
  return (
    <div
      style={{
        position: "absolute", left: 860, top: 840, padding: "26px 40px", borderRadius: 30,
        background: "rgba(94,230,217,0.16)", border: `2px solid ${TEAL}`, fontFamily: FONT,
        fontSize: 58, fontWeight: 800, color: "white", opacity: p,
        translate: `${(1 - p) * -30}px 0px`, boxShadow: "0 0 60px rgba(94,230,217,0.25)",
      }}
    >
      {text}
    </div>
  );
};

export const AskMujiScene: React.FC = () => {
  const q = "How much did I spend at Muji?";
  const t = 14 + typed(q);
  return (
    <AskScene
      question={q}
      title="Just ask"
      lines={["It searches with tools,", "then reads the receipt"]}
      shots={[{ src: "ask-muji", at: t + 6, zoom: { x: 600, y: 690, scale: 1.2, at: t + 30 } }]}
      answer="Total: HK$702.00"
      answerAt={t + 34}
    />
  );
};

export const AskTrainScene: React.FC = () => {
  const q = "When does my train to Shanghai leave?";
  const t = 14 + typed(q);
  return (
    <AskScene
      question={q}
      title="Reads screenshots"
      lines={["Finds the booking,", "then reads the time"]}
      shots={[{ src: "ask-train", at: t + 6, zoom: { x: 600, y: 690, scale: 1.2, at: t + 30 } }]}
      answer="Friday 19 Dec, 08:15"
      answerAt={t + 34}
    />
  );
};

export const AskAlbumScene: React.FC = () => {
  const q = "Put my photos from the Tokyo trip in an album";
  const t = 14 + typed(q);
  return (
    <AskScene
      question={q}
      title="It organises too"
      lines={["You confirm with one tap"]}
      shots={[
        { src: "ask-tokyo", at: t + 6 },
        { src: "ask-tokyo-saved", at: t + 70, zoom: { x: 700, y: 1890, scale: 1.15, at: t + 90 } },
      ]}
      answer="✓ Saved · Tokyo Trip"
      answerAt={t + 94}
    />
  );
};

export const EditScene: React.FC = () => {
  const q = "brighter, warmer and more vivid";
  const t = 14 + typed(q);
  return (
    <AbsoluteFill>
      <Phone shots={[{ src: "edit-before", at: 0 }, { src: "edit-after", at: t + 8 }]} />
      <SideText eyebrow="Edit" title="Describe the change" lines={["Done on the phone, for free"]} />
      <TypedField text={q} at={14} x={860} y={760} />
      <Footnote />
    </AbsoluteFill>
  );
};

export const PrivacyScene: React.FC = () => (
  <AbsoluteFill>
    <Phone shots={[
      { src: "settings-picker", at: 0 },
      { src: "settings-warning", at: 130, zoom: { x: 660, y: 1480, scale: 1.25, at: 160 } },
    ]} />
    <SideText eyebrow="Privacy" title="On the phone by default" lines={["Apple Intelligence, or a small", "open model for older iPhones", "A clear warning before any upload"]} />
    <Footnote />
  </AbsoluteFill>
);

// MARK: 14 · Results

const Bar: React.FC<{ label: string; before: number; after: number; at: number; y: number }> = ({ label, before, after, at, y }) => {
  const p = useIn(at, 40);
  const show = useIn(at, 12);
  const w = 560;
  return (
    <div style={{ position: "absolute", left: 140, top: y, fontFamily: FONT, opacity: show }}>
      <div style={{ color: "white", fontSize: 40, width: 640 }}>{label}</div>
      <div style={{ position: "absolute", left: 700, top: -6, display: "flex", flexDirection: "column", gap: 12 }}>
        {[[before, "rgba(170,170,210,0.9)", "first version"], [after, TEAL, "Phophy now"]].map(([v, c, name]) => (
          <div key={name as string} style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <div style={{ width: w, height: 26, borderRadius: 13, background: "rgba(255,255,255,0.08)" }}>
              <div style={{ width: Math.max(8, w * (v as number) * p), height: 26, borderRadius: 13, background: c as string }} />
            </div>
            <div style={{ color: c as string, fontSize: 34, fontWeight: 700, width: 110, fontVariantNumeric: "tabular-nums" }}>
              {Math.round((v as number) * p * 100)}%
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export const ResultsScene: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: FONT }}>
    <Rise at={2}>
      <div style={{ position: "absolute", left: 140, top: 80, color: "white", fontSize: 76, fontWeight: 800 }}>Search, measured</div>
    </Rise>
    <Rise at={10}>
      <div style={{ position: "absolute", left: 142, top: 185, color: SOFT, fontSize: 36 }}>
        Flickr30k benchmark · 1,000 photos · 362 searches
      </div>
    </Rise>
    <Rise at={14}>
      <div style={{ position: "absolute", left: 840, top: 260, display: "flex", gap: 40, fontSize: 30 }}>
        <span style={{ color: "rgba(170,170,210,0.95)" }}>■ first version</span>
        <span style={{ color: TEAL }}>■ Phophy now</span>
      </div>
    </Rise>
    <Bar label="Chinese searches, top-10 correct" before={0.02} after={0.51} at={150} y={340} />
    <Bar label="Misspelled searches, top-10 correct" before={0.13} after={0.59} at={250} y={510} />
    <Bar label="Objects found in the top 50" before={0.51} after={0.89} at={330} y={680} />
    <Bar label="Long descriptions, right photo first" before={0.76} after={0.77} at={430} y={850} />
  </AbsoluteFill>
);

// MARK: 15 · On a real iPhone

const Stat: React.FC<{ at: number; big: React.ReactNode; label: string; x: number }> = ({ at, big, label, x }) => (
  <Rise at={at}>
    <div style={{ position: "absolute", left: x, top: 420, width: 400, fontFamily: FONT }}>
      <div style={{ color: TEAL, fontSize: 110, fontWeight: 800, fontVariantNumeric: "tabular-nums" }}>{big}</div>
      <div style={{ color: SOFT, fontSize: 38, marginTop: 6, lineHeight: 1.3 }}>{label}</div>
    </div>
  </Rise>
);

export const PhoneSpeedScene: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: FONT }}>
    <Rise at={2}>
      <div style={{ position: "absolute", left: 140, top: 110, color: "white", fontSize: 76, fontWeight: 800 }}>On a real iPhone 13 Pro Max</div>
    </Rise>
    <Rise at={10}>
      <div style={{ position: "absolute", left: 142, top: 215, color: SOFT, fontSize: 36 }}>No Apple Intelligence · 16,080 photos</div>
    </Rise>
    <Stat at={60} x={140} big={<><span>&lt;</span><Count to={25} at={60} /> ms</>} label="per search" />
    <Stat at={130} x={620} big={<><Count to={1.5} at={130} decimals={1} /> s</>} label="to describe a photo, on the phone" />
    <Stat at={200} x={1140} big={<Count to={0} at={200} />} label="photos uploaded" />
  </AbsoluteFill>
);

// MARK: 16 · Thanks

export const ThanksScene: React.FC = () => {
  const team = [
    ["Su Chuanzhou", "Lead · design, integration, Study"],
    ["Yin Fengling", "Indexing and performance"],
    ["Qin Mengmeng", "Search and assistant"],
    ["Wang Zhengyao", "Viewer, editor and collections"],
  ];
  return (
    <AbsoluteFill style={{ fontFamily: FONT, padding: "120px 160px" }}>
      <Rise at={2}>
        <div style={{ color: "white", fontSize: 96, fontWeight: 800 }}>Thank you</div>
      </Rise>
      <Rise at={8}>
        <div style={{ color: TEAL, fontSize: 34, fontWeight: 700, marginTop: 10, letterSpacing: 2 }}>TEAM 26 · github.com/Jasonsu22/Phophy</div>
      </Rise>
      <div style={{ marginTop: 60 }}>
        {team.map(([name, role], i) => (
          <Rise key={name} at={20 + i * 10}>
            <div style={{ display: "flex", gap: 40, alignItems: "baseline", marginTop: 26 }}>
              <div style={{ color: "white", fontSize: 50, fontWeight: 700, width: 420 }}>{name}</div>
              <div style={{ color: SOFT, fontSize: 40 }}>{role}</div>
            </div>
          </Rise>
        ))}
      </div>
    </AbsoluteFill>
  );
};

