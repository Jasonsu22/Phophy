import React from "react";
import { Composition } from "remotion";
import { PhophyVideo, totalFrames } from "./Video";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="PhophyDemo"
        component={PhophyVideo}
        durationInFrames={totalFrames(30)}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
