import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile } from "remotion";
import { Callout, Count, DIM, FONT, Footnote, Heading, Phone, PhoneFrame, Rise, SCREEN, SOFT, Side, Steps, TEAL, Typed, Words, useIn, useTime } from "./ui";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const OUT = Easing.bezier(0.16, 1, 0.3, 1);

// MARK: Title

export const PhotoTile: React.FC<{ n: number; i: number }> = ({ n, i }) => {
  const t = useTime();
  const col = i % 6;
  const row = Math.floor(i / 6);
  const p = useIn(i * 0.05, 1);
  const drift = t * 12 * (row % 2 === 0 ? 1 : -1);
  return (
    <Img
      src={staticFile(`photos/p${n}.jpg`)}
      style={{
        position: "absolute", width: 300, height: 300, borderRadius: 36, objectFit: "cover",
        left: -80 + col * 340 + drift + (row % 2) * 170, top: 40 + row * 340, opacity: p * 0.42,
        rotate: `${(i % 3) - 1}deg`, scale: String(interpolate(p, [0, 1], [0.8, 1])),
        boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
      }}
    />
  );
};

export const TitleScene: React.FC = () => (
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
        <div style={{ fontSize: 32, color: TEAL, marginTop: 70, fontWeight: 700, letterSpacing: 4 }}>TEAM 26</div>
      </Rise>
    </AbsoluteFill>
  </AbsoluteFill>
);

// MARK: Scenario 1 · the photo you can't find

const GRID = { photos: 160, columns: 4, gap: 2 };

/**
 * The whole library as a grid, scrolled by hand: each flick starts fast and
 * glides to a stop, as a finger's does. Drawn in code, so every frame of the
 * scroll is exact.
 */
export const AlbumScreen: React.FC<{ plan?: (bottom: number) => number[][] }> = ({ plan }) => {
  const t = useTime();
  const tile = (SCREEN.width - GRID.gap * (GRID.columns - 1)) / GRID.columns;
  const rows = GRID.photos / GRID.columns;
  const bottom = rows * (tile + GRID.gap) + 150 - SCREEN.height;
  // [starts, lasts, where the flick ends]: up through the months, back, up again.
  const flicks = plan?.(bottom) ?? [
    [0.9, 1.5, bottom - 760], [2.3, 1.5, bottom - 1650], [3.7, 1.6, bottom - 2600], [5.2, 1.5, 120],
    [6.7, 1.4, 1150], [8.0, 1.4, 2100], [9.3, 1.3, 1500],
  ];
  let offset = bottom;
  for (const [at, lasts, to] of flicks) {
    offset = interpolate(t, [at, at + lasts], [offset, to], { ...clamp, easing: Easing.bezier(0.2, 0.85, 0.3, 1) });
  }
  const first = Math.max(0, Math.floor((offset - 110) / (tile + GRID.gap)) - 1);
  const visible = Array.from({ length: (Math.ceil(SCREEN.height / tile) + 3) * GRID.columns }, (_, i) => first * GRID.columns + i).filter((i) => i < GRID.photos);
  return (
    <AbsoluteFill style={{ background: "#0d0b24", fontFamily: FONT }}>
      {visible.map((i) => (
        <Img
          key={i}
          src={staticFile(`grid/g${i + 1}.jpg`)}
          style={{
            position: "absolute", width: tile, height: tile, objectFit: "cover",
            left: (i % GRID.columns) * (tile + GRID.gap), top: 110 + Math.floor(i / GRID.columns) * (tile + GRID.gap) - offset,
          }}
        />
      ))}
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 150, background: "linear-gradient(#1a1250 30%, rgba(26,18,80,0))" }} />
      <div style={{ position: "absolute", left: 30, top: 16, color: "white", fontSize: 17, fontWeight: 600 }}>9:41</div>
      <div style={{ position: "absolute", left: (SCREEN.width - 96) / 2, top: 12, width: 96, height: 28, borderRadius: 14, background: "#000" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: 56, textAlign: "center", color: "white", fontSize: 18, fontWeight: 600 }}>All Photos</div>
      <div
        style={{
          position: "absolute", left: 16, top: 48, width: 38, height: 38, borderRadius: 19, background: "rgba(124,92,255,0.75)",
          color: "white", fontSize: 24, textAlign: "center", lineHeight: "34px",
        }}
      >
        ‹
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 170, background: "linear-gradient(rgba(60,20,70,0), rgba(60,20,70,0.9))" }} />
      <div
        style={{
          position: "absolute", left: 18, right: 18, bottom: 26, height: 50, borderRadius: 25, background: "rgba(255,255,255,0.14)",
          border: "1px solid rgba(255,255,255,0.22)", color: "rgba(255,255,255,0.6)", fontSize: 17, lineHeight: "48px", paddingLeft: 22,
        }}
      >
        ✦ Search or ask about your photos
      </div>
    </AbsoluteFill>
  );
};

export const HuntScene: React.FC<{ note?: string }> = ({ note = "The library as an animation; every other scene is recorded in the app" }) => {
  const t = useTime();
  // A clock that runs while the phone scrolls: minutes of looking, shown fast.
  const looked = interpolate(t, [1.6, 9.2], [0, 154], clamp);
  const giveUp = useIn(8.4, 0.7);
  return (
    <AbsoluteFill>
      <PhoneFrame>
        <AlbumScreen />
      </PhoneFrame>
      <Side top={210}>
        <Heading eyebrow="Scenario 1" title="“Where is that whiteboard photo from last month?”" size={74} />
        <Rise at={1.4}>
          <div style={{ marginTop: 50, fontSize: 40, color: SOFT }}>You remember what was in it. Not where it is.</div>
        </Rise>
        <Rise at={1.9}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 26, marginTop: 44 }}>
            <div style={{ fontSize: 120, fontWeight: 800, color: "white", fontVariantNumeric: "tabular-nums" }}>
              {Math.floor(looked / 60)}:{String(Math.floor(looked % 60)).padStart(2, "0")}
            </div>
            <div style={{ fontSize: 40, color: DIM }}>of scrolling</div>
          </div>
        </Rise>
        <div style={{ opacity: giveUp, translate: `0px ${(1 - giveUp) * 24}px`, marginTop: 16, fontSize: 46, fontWeight: 700, color: "#FFB4A8" }}>
          Still not found. It is buried.
        </div>
      </Side>
      <Footnote text={note} />
    </AbsoluteFill>
  );
};

export const FindScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="find" />
    <Side top={230}>
      <Heading eyebrow="With Phophy" title="Type what you remember" />
      <Typed text="whiteboard from last month" at={0.3} />
      <Steps
        items={[
          { at: 2.7, text: "Matching photos appear at once" },
          { at: 3.9, text: "Then the answer: where, when, what’s on it" },
          { at: 7.0, text: "Found: 29 October, the network diagram" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

// MARK: Scenario 2 · today's lecture

const SlideCard: React.FC<{ n: number; dealAt: number; pileAt: number }> = ({ n, dealAt, pileAt }) => {
  const t = useTime();
  const i = n - 1;
  // Dealt out in a row, then swept into a pile that sinks away.
  const deal = interpolate(t, [dealAt + i * 0.12, dealAt + 0.8 + i * 0.12], [0, 1], { ...clamp, easing: OUT });
  const pile = interpolate(t, [pileAt + i * 0.05, pileAt + 1 + i * 0.05], [0, 1], { ...clamp, easing: Easing.bezier(0.6, 0, 0.3, 1) });
  const rowX = 150 + i * 236;
  const rowY = 470 + (i % 2) * 34;
  const x = interpolate(pile, [0, 1], [rowX, 1290 + i * 9]);
  const y = interpolate(pile, [0, 1], [rowY, 600 - i * 8]) + (1 - deal) * 500;
  return (
    <Img
      src={staticFile(`slides/s${n}.jpg`)}
      style={{
        position: "absolute", left: x, top: y, width: 330, height: 248, objectFit: "cover", borderRadius: 22,
        border: "3px solid rgba(255,255,255,0.85)", boxShadow: "0 30px 70px rgba(0,0,0,0.5)", opacity: deal,
        rotate: `${interpolate(pile, [0, 1], [((i * 37) % 9) - 4, ((i * 53) % 15) - 7])}deg`,
        scale: String(interpolate(pile, [0, 1], [1, 1.25])), filter: `saturate(${1 - pile * 0.5}) brightness(${1 - pile * 0.3})`,
      }}
    />
  );
};

export const LectureIntroScene: React.FC<{ dealAt?: number; pileAt?: number }> = ({ dealAt = 0.9, pileAt = 4.6 }) => {
  const label = useIn(pileAt + 1, 0.8);
  return (
    <AbsoluteFill style={{ fontFamily: FONT }}>
      <div style={{ position: "absolute", left: 150, top: 110, width: 1500 }}>
        <Heading eyebrow="Scenario 2" title="Today’s lecture: seven slides, photographed from your seat" size={72} />
      </div>
      {[1, 2, 3, 4, 5, 6, 7].map((n) => (
        <SlideCard key={n} n={n} dealAt={dealAt} pileAt={pileAt} />
      ))}
      <div style={{ position: "absolute", left: 150, top: 540, width: 1100, opacity: label, translate: `0px ${(1 - label) * 26}px` }}>
        <div style={{ fontSize: 84, fontWeight: 800, color: "white" }}>Into the camera roll.</div>
        <div style={{ fontSize: 60, color: "#FFB4A8", fontWeight: 700, marginTop: 18 }}>Never opened again.</div>
      </div>
    </AbsoluteFill>
  );
};

export const AskLectureScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="ask-lecture" />
    <Side top={230}>
      <Heading eyebrow="With Phophy" title="Ask for the lecture back" />
      <Typed text="Summarise the slides from today’s lecture" at={0.2} perSecond={34} />
      <Steps
        items={[
          { at: 2.3, text: "Finds today’s slides among everything else" },
          { at: 4.3, text: "Reads them and sums them up" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

export const NotesScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="notes" />
    <Side top={230}>
      <Heading eyebrow="Study" title="Slides become notes" />
      <Steps
        top={56}
        items={[
          { at: 0.6, text: "One tap: Make notes" },
          { at: 2.1, text: "A summary, written on the phone" },
          { at: 6.2, text: "Key points, each with its slide number" },
          { at: 11.1, text: "Flashcards to revise before the quiz" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

// MARK: More it can do

export const MujiScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="muji" />
    <Side>
      <Heading eyebrow="Ask" title="Answers from what’s in the photo" size={78} />
      <Typed text="How much did I spend at Muji?" at={0.2} perSecond={34} />
      <div>
        <Callout at={2.9} label="Read from the receipt" value="HK$702.00" />
      </div>
    </Side>
    <Footnote />
  </AbsoluteFill>
);

export const EditScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="edit" />
    <Side top={230}>
      <Heading eyebrow="Edit" title="Describe the change" />
      <Typed text="warmer and more vivid" at={0.2} icon="✎" />
      <Steps
        items={[
          { at: 2.2, text: "Understood and applied on the iPhone" },
          { at: 5.4, text: "Bigger changes: your own AI image service, working in the background" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

export const CollectionsScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="collections" />
    <Side>
      <Heading eyebrow="Collections" title="Sorted for you" />
      <Steps
        top={56}
        items={[
          { at: 0.8, text: "Slides, receipts, documents, people, pets" },
          { at: 8.3, text: "Near-identical shots, with one to keep" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

export const PlaceScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="place" />
    <Side top={230}>
      <Heading eyebrow="Search" title="Places and dates, in plain words" size={78} />
      <Typed text="Tokyo in May" at={0.2} />
      <Steps
        items={[
          { at: 2.5, text: "The place and the month, understood" },
          { at: 4.8, text: "Every result, as an album" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

export const PrivacyScene: React.FC = () => (
  <AbsoluteFill>
    <Phone clip="settings" />
    <Side>
      <Heading eyebrow="Privacy" title="On the phone by default" />
      <Steps
        top={56}
        items={[
          { at: 0.8, text: "Apple Intelligence: free, private, offline" },
          { at: 2.6, text: "A small open model for older iPhones" },
          { at: 4.4, text: "Cloud AI only if you turn it on" },
        ]}
      />
    </Side>
    <Footnote />
  </AbsoluteFill>
);

// MARK: Results

export const Bar: React.FC<{ label: string; before: number; after: number; at: number; y: number }> = ({ label, before, after, at, y }) => {
  const p = useIn(at, 1.4);
  const show = useIn(at, 0.5);
  const w = 560;
  return (
    <div style={{ position: "absolute", left: 140, top: y, fontFamily: FONT, opacity: show, translate: `0px ${(1 - show) * 20}px` }}>
      <div style={{ color: "white", fontSize: 40, width: 640 }}>{label}</div>
      <div style={{ position: "absolute", left: 700, top: -6, display: "flex", flexDirection: "column", gap: 12 }}>
        {([[before, "rgba(170,170,210,0.9)", "first"], [after, TEAL, "now"]] as const).map(([v, c, name]) => (
          <div key={name} style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <div style={{ width: w, height: 26, borderRadius: 13, background: "rgba(255,255,255,0.08)" }}>
              <div style={{ width: Math.max(8, w * v * p), height: 26, borderRadius: 13, background: c }} />
            </div>
            <div style={{ color: c, fontSize: 34, fontWeight: 700, width: 110, fontVariantNumeric: "tabular-nums" }}>{Math.round(v * p * 100)}%</div>
          </div>
        ))}
      </div>
    </div>
  );
};

export const ResultsScene: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: FONT }}>
    <div style={{ position: "absolute", left: 140, top: 80 }}>
      <Words text="Search, measured" at={0.1} style={{ color: "white", fontSize: 76, fontWeight: 800 }} />
    </div>
    <Rise at={0.4}>
      <div style={{ position: "absolute", left: 142, top: 185, color: SOFT, fontSize: 36 }}>Flickr30k benchmark · 1,000 photos · 362 searches</div>
    </Rise>
    <Rise at={0.6}>
      <div style={{ position: "absolute", left: 840, top: 260, display: "flex", gap: 40, fontSize: 30 }}>
        <span style={{ color: "rgba(170,170,210,0.95)" }}>■ first version</span>
        <span style={{ color: TEAL }}>■ Phophy now</span>
      </div>
    </Rise>
    <Bar label="Chinese searches, top-10 correct" before={0.02} after={0.51} at={1.6} y={340} />
    <Bar label="Misspelled searches, top-10 correct" before={0.13} after={0.59} at={4.4} y={510} />
    <Bar label="Objects found in the top 50" before={0.51} after={0.89} at={7.2} y={680} />
    <Bar label="Long descriptions, right photo first" before={0.76} after={0.77} at={10} y={850} />
  </AbsoluteFill>
);

export const Stat: React.FC<{ at: number; big: React.ReactNode; label: string; x: number }> = ({ at, big, label, x }) => (
  <Rise at={at}>
    <div style={{ position: "absolute", left: x, top: 420, width: 400, fontFamily: FONT }}>
      <div style={{ color: TEAL, fontSize: 110, fontWeight: 800, fontVariantNumeric: "tabular-nums" }}>{big}</div>
      <div style={{ color: SOFT, fontSize: 38, marginTop: 6, lineHeight: 1.3 }}>{label}</div>
    </div>
  </Rise>
);

export const PhoneSpeedScene: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: FONT }}>
    <div style={{ position: "absolute", left: 140, top: 110 }}>
      <Words text="On a real iPhone 13 Pro Max" at={0.1} style={{ color: "white", fontSize: 76, fontWeight: 800 }} />
    </div>
    <Rise at={0.4}>
      <div style={{ position: "absolute", left: 142, top: 215, color: SOFT, fontSize: 36 }}>No Apple Intelligence · a library of 16,000 photos</div>
    </Rise>
    <Stat at={1.2} x={140} big={<><span>&lt;</span><Count to={25} at={1.2} /> ms</>} label="per search" />
    <Stat at={3.2} x={620} big={<><Count to={1.5} at={3.2} decimals={1} /> s</>} label="to describe a photo, on the phone" />
    <Stat at={5.2} x={1140} big={<Count to={0} at={5.2} />} label="photos uploaded" />
  </AbsoluteFill>
);

// MARK: Thanks

export const ThanksScene: React.FC = () => {
  const team = [
    ["Wang Zhengyao", "3036795675", "Viewer, editor and collections"],
    ["Yin Fengling", "3036807375", "Indexing and performance"],
    ["Qin Mengmeng", "3036843769", "Search and assistant"],
    ["Su Chuanzhou", "3036837980", "Lead · design, integration, Study"],
  ];
  return (
    <AbsoluteFill style={{ fontFamily: FONT, padding: "120px 160px" }}>
      <Words text="Thank you" at={0.1} style={{ color: "white", fontSize: 96, fontWeight: 800 }} />
      <Rise at={0.4}>
        <div style={{ color: TEAL, fontSize: 34, fontWeight: 700, marginTop: 10, letterSpacing: 2 }}>TEAM 26 · github.com/Jasonsu22/Phophy</div>
      </Rise>
      <div style={{ marginTop: 60 }}>
        {team.map(([name, id, role], i) => (
          <Rise key={name} at={0.8 + i * 0.25}>
            <div style={{ display: "flex", gap: 40, alignItems: "baseline", marginTop: 26 }}>
              <div style={{ color: "white", fontSize: 50, fontWeight: 700, width: 420 }}>{name}</div>
              <div style={{ color: TEAL, fontSize: 40, width: 260, fontVariantNumeric: "tabular-nums" }}>{id}</div>
              <div style={{ color: SOFT, fontSize: 36 }}>{role}</div>
            </div>
          </Rise>
        ))}
      </div>
    </AbsoluteFill>
  );
};
