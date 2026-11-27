import React from "react";
import { Composition } from "remotion";
import { PhophyVideo, totalFrames } from "./Video";
import { PAGES, TalkPage, TalkVideo, talkFrames } from "./Talk";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* The two-minute product demo. */}
      <Composition
        id="PhophyDemo"
        component={PhophyVideo}
        durationInFrames={totalFrames(60)}
        fps={60}
        width={1920}
        height={1080}
      />
      {/* The five-minute project presentation. */}
      <Composition
        id="PhophyTalk"
        component={TalkVideo}
        durationInFrames={talkFrames(60)}
        fps={60}
        width={1920}
        height={1080}
      />
      {/* One page of the presentation: pass {"page": 0} for the first. */}
      <Composition
        id="TalkPage"
        component={TalkPage}
        durationInFrames={60}
        fps={60}
        width={1920}
        height={1080}
        defaultProps={{ page: 0 }}
        calculateMetadata={({ props }) => ({ durationInFrames: Math.round(PAGES[props.page].seconds * 60) })}
      />
    </>
  );
};
