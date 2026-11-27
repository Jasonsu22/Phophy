import React from "react";
import { AbsoluteFill, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import talk from "./talk.json";
import timing from "./talk-timing.json";
import { Background, FONT, Sfx, TEAL } from "./ui";
import {
  AgentScene, AskTalk, AssistantScene, BuiltScene, ChineseScene, CollectionsTalk, EditTalk, FindTalk, GoalScene, HuntTalk, HybridScene,
  IndexScene, LanguageScene, LectureTalk, MujiTalk, NextScene, NotesEditsScene, NotesTalk, QueryScene, ResultsTalk, ThanksTalk, TiersScene,
  TitleTalk, WhyScene,
} from "./talkPages";

// The five-minute project presentation: motivation, methodology,
// implementation and key results. The pages, their order and their narration
// are in talk.json; make_talk.py speaks the narration and writes each page's
// length to talk-timing.json.

const SCENES: Record<string, React.FC> = {
  title: TitleTalk,
  scenario1: HuntTalk,
  scenario2: LectureTalk,
  why: WhyScene,
  goal: GoalScene,
  tiers: TiersScene,
  index: IndexScene,
  hybrid: HybridScene,
  query: QueryScene,
  assistant: AssistantScene,
  notes: NotesEditsScene,
  built: BuiltScene,
  find: FindTalk,
  ask: AskTalk,
  makenotes: NotesTalk,
  receipt: MujiTalk,
  chinese: ChineseScene,
  edit: EditTalk,
  collections: CollectionsTalk,
  "results-search": ResultsTalk,
  "results-language": LanguageScene,
  "results-assistant": AgentScene,
  next: NextScene,
  thanks: ThanksTalk,
};

export const PAGES = talk.pages.map((page, i) => ({
  id: page.id,
  part: page.part,
  name: page.title,
  seconds: timing.pages[i].seconds,
  Scene: SCENES[page.id],
}));

export const TRANSITION = timing.transition;

export const talkFrames = (fps: number) =>
  PAGES.reduce((sum, p) => sum + Math.round(p.seconds * fps), 0) - Math.round(TRANSITION * fps) * (PAGES.length - 1);

/** Where the talk is: the four parts the presentation has to cover, with the current one lit. */
export const PartBar: React.FC<{ part: string }> = ({ part }) => {
  const active = talk.parts.indexOf(part);
  if (active < 0) return null;
  return (
    <div style={{ position: "absolute", right: 64, bottom: 28, display: "flex", alignItems: "center", gap: 14, fontFamily: FONT, fontSize: 22, letterSpacing: 1 }}>
      {talk.parts.map((name, i) => (
        <React.Fragment key={name}>
          {i > 0 ? <div style={{ width: 30, height: 2, background: i <= active ? TEAL : "rgba(226,232,255,0.25)" }} /> : null}
          <div
            style={{
              display: "flex", alignItems: "center", gap: 10, fontWeight: i === active ? 700 : 500,
              color: i === active ? "white" : i < active ? "rgba(226,232,255,0.62)" : "rgba(226,232,255,0.36)",
            }}
          >
            <div
              style={{
                width: 14, height: 14, borderRadius: 7, boxSizing: "border-box", background: i <= active ? TEAL : "transparent",
                border: `2px solid ${i <= active ? TEAL : "rgba(226,232,255,0.36)"}`, boxShadow: i === active ? `0 0 16px ${TEAL}` : undefined,
              }}
            />
            {name}
          </div>
        </React.Fragment>
      ))}
    </div>
  );
};

export const TalkVideo: React.FC = () => {
  const { fps } = useVideoConfig();
  const frame = useCurrentFrame();
  // The part shown is the page that is mostly on screen: it changes halfway through a fade.
  let start = 0;
  let current = PAGES[0];
  for (const page of PAGES) {
    if (frame >= start - Math.round((TRANSITION / 2) * fps)) current = page;
    start += Math.round(page.seconds * fps) - Math.round(TRANSITION * fps);
  }
  return (
    <AbsoluteFill style={{ backgroundColor: "#140f3a" }}>
      <Background />
      <TransitionSeries>
        {PAGES.flatMap(({ id, name, seconds, Scene }, i) => {
          const items = [
            <TransitionSeries.Sequence key={id} name={name} durationInFrames={Math.round(seconds * fps)}>
              <Scene />
              {/* A new part of the talk arrives with a soft whoosh. */}
              {i > 0 && PAGES[i - 1].part !== PAGES[i].part ? <Sfx name="whoosh" at={0.05} volume={0.26} /> : null}
              <Sequence from={Math.round(timing.lead * fps)} name={`Voice ${String(i + 1).padStart(2, "0")}`}>
                <Audio src={staticFile(`voice-talk/${String(i + 1).padStart(2, "0")}.m4a`)} />
              </Sequence>
            </TransitionSeries.Sequence>,
          ];
          if (i < PAGES.length - 1) {
            items.push(
              <TransitionSeries.Transition key={`${id}-fade`} presentation={fade()} timing={linearTiming({ durationInFrames: Math.round(TRANSITION * fps) })} />,
            );
          }
          return items;
        })}
      </TransitionSeries>
      <PartBar part={current.part} />
    </AbsoluteFill>
  );
};

/** One page on its own, for the storyboard's preview frames and for working on a page in the Studio. */
export const TalkPage: React.FC<{ page: number }> = ({ page }) => {
  const { part, Scene } = PAGES[Math.max(0, Math.min(PAGES.length - 1, page))];
  return (
    <AbsoluteFill style={{ backgroundColor: "#140f3a" }}>
      <Background />
      <Scene />
      <PartBar part={part} />
    </AbsoluteFill>
  );
};
