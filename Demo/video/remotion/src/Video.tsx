import React from "react";
import { AbsoluteFill, Sequence, staticFile, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";
import { TransitionSeries, springTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { Background } from "./ui";
import {
  AskAlbumScene, AskMujiScene, AskTrainScene, CollectionsScene, EditScene, HowScene, LibraryScene,
  PhoneSpeedScene, PrivacyScene, ProblemScene, ResultsScene, SearchMeaningScene, SearchTextScene,
  StudyScene, ThanksScene, TitleScene,
} from "./scenes";

/** Scene lengths in seconds; each scene's narration starts 0.4 s in. */
export const SCENES: { name: string; seconds: number; Scene: React.FC }[] = [
  { name: "Title", seconds: 7, Scene: TitleScene },
  { name: "Problem", seconds: 12.5, Scene: ProblemScene },
  { name: "How it works", seconds: 15, Scene: HowScene },
  { name: "Library", seconds: 11, Scene: LibraryScene },
  { name: "Search by meaning", seconds: 13.5, Scene: SearchMeaningScene },
  { name: "Words in photos", seconds: 12, Scene: SearchTextScene },
  { name: "Collections", seconds: 12.5, Scene: CollectionsScene },
  { name: "Study", seconds: 14.5, Scene: StudyScene },
  { name: "Ask: Muji", seconds: 7.5, Scene: AskMujiScene },
  { name: "Ask: train", seconds: 7, Scene: AskTrainScene },
  { name: "Ask: album", seconds: 9, Scene: AskAlbumScene },
  { name: "Edit", seconds: 7, Scene: EditScene },
  { name: "Privacy", seconds: 13, Scene: PrivacyScene },
  { name: "Results", seconds: 23, Scene: ResultsScene },
  { name: "iPhone speed", seconds: 12, Scene: PhoneSpeedScene },
  { name: "Thanks", seconds: 8.5, Scene: ThanksScene },
];

export const TRANSITION = 15;

export const totalFrames = (fps: number) =>
  SCENES.reduce((sum, s) => sum + Math.round(s.seconds * fps), 0) - TRANSITION * (SCENES.length - 1);

export const PhophyVideo: React.FC = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: "#140f3a" }}>
      <Background />
      <TransitionSeries>
        {SCENES.flatMap(({ name, seconds, Scene }, i) => {
          const n = String(i + 1).padStart(2, "0");
          const items = [
            <TransitionSeries.Sequence key={name} name={name} durationInFrames={Math.round(seconds * fps)}>
              <Scene />
              <Sequence from={Math.round(0.4 * fps)} name={`Voice ${n}`}>
                <Audio src={staticFile(`voice/${n}.m4a`)} />
              </Sequence>
            </TransitionSeries.Sequence>,
          ];
          if (i < SCENES.length - 1) {
            items.push(
              <TransitionSeries.Transition
                key={`${name}-fade`}
                presentation={fade()}
                timing={springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION })}
              />,
            );
          }
          return items;
        })}
      </TransitionSeries>
    </AbsoluteFill>
  );
};
