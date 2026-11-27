import React from "react";
import { AbsoluteFill, Sequence, staticFile, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { Background } from "./ui";
import clips from "./clips.json";
import {
  AskLectureScene, CollectionsScene, EditScene, FindScene, HuntScene, LectureIntroScene, MujiScene, NotesScene,
  PhoneSpeedScene, PlaceScene, PrivacyScene, ResultsScene, ThanksScene, TitleScene,
} from "./scenes";

/**
 * Scene lengths in seconds. A scene with a recording lasts as long as its clip.
 * Each scene's narration (public/voice/NN.m4a, from make_voice.py) starts 0.45 s in.
 */
export const SCENES: { name: string; seconds: number; Scene: React.FC }[] = [
  { name: "Title", seconds: 5, Scene: TitleScene },
  { name: "Scenario 1: scrolling", seconds: 10.5, Scene: HuntScene },
  { name: "Scenario 1: found", seconds: clips.find, Scene: FindScene },
  { name: "Scenario 2: the slides", seconds: 8.5, Scene: LectureIntroScene },
  { name: "Scenario 2: ask", seconds: clips["ask-lecture"], Scene: AskLectureScene },
  { name: "Scenario 2: notes", seconds: clips.notes, Scene: NotesScene },
  { name: "Ask: receipt", seconds: clips.muji, Scene: MujiScene },
  { name: "Edit", seconds: clips.edit, Scene: EditScene },
  { name: "Collections", seconds: clips.collections, Scene: CollectionsScene },
  { name: "Place and time", seconds: clips.place, Scene: PlaceScene },
  { name: "Privacy", seconds: clips.settings, Scene: PrivacyScene },
  { name: "Results", seconds: 16.5, Scene: ResultsScene },
  { name: "iPhone speed", seconds: 8, Scene: PhoneSpeedScene },
  { name: "Thanks", seconds: 6, Scene: ThanksScene },
];

/** Seconds two scenes overlap while one fades into the next. */
export const TRANSITION = 0.5;

export const totalFrames = (fps: number) =>
  SCENES.reduce((sum, s) => sum + Math.round(s.seconds * fps), 0) - Math.round(TRANSITION * fps) * (SCENES.length - 1);

export const PhophyVideo: React.FC = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: "#140f3a" }}>
      <Background />
      <TransitionSeries>
        {SCENES.flatMap(({ name, seconds, Scene }, i) => {
          const items = [
            <TransitionSeries.Sequence key={name} name={name} durationInFrames={Math.round(seconds * fps)}>
              <Scene />
              <Sequence from={Math.round(0.45 * fps)} name={`Voice ${String(i + 1).padStart(2, "0")}`}>
                <Audio src={staticFile(`voice/${String(i + 1).padStart(2, "0")}.m4a`)} />
              </Sequence>
            </TransitionSeries.Sequence>,
          ];
          if (i < SCENES.length - 1) {
            items.push(
              <TransitionSeries.Transition
                key={`${name}-fade`}
                presentation={fade()}
                timing={linearTiming({ durationInFrames: Math.round(TRANSITION * fps) })}
              />,
            );
          }
          return items;
        })}
      </TransitionSeries>
    </AbsoluteFill>
  );
};
