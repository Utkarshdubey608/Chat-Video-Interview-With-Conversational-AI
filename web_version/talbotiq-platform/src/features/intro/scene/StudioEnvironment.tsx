import { Environment, Lightformer } from '@react-three/drei'

import { PALETTE } from '../constants'

/**
 * Fully programmatic studio lighting — the biggest lever for the "KeyShot"
 * look, with no HDRI download. Four Lightformer panels (a warm overhead
 * softbox, two cool side rim strips and a low warm fill) are baked once into a
 * small PMREM environment so every surface picks up believable image-based
 * reflections and soft light. A key spot + rim spot add crisp edge definition
 * on the hero wordmark; a dim ambient lifts the shadows just off black.
 *
 * `frames={1}` bakes the environment a single time (it never moves), keeping
 * this effectively free per frame.
 */
export function StudioEnvironment({ accentColor }: { accentColor: string }) {
  return (
    <>
      <ambientLight intensity={0.12} />

      {/* Key — warm, high and to the right, soft penumbra. */}
      <spotLight
        position={[6, 9, 7]}
        angle={0.42}
        penumbra={1}
        decay={2}
        intensity={420}
        color={PALETTE.key}
        castShadow
        shadow-mapSize={[1024, 1024]}
        shadow-bias={-0.0002}
      />
      {/* Cool rim from behind-left for edge separation. */}
      <spotLight
        position={[-8, 5, -6]}
        angle={0.5}
        penumbra={1}
        decay={2}
        intensity={260}
        color={PALETTE.rimCool}
      />
      {/* A whisper of accent-coloured up-light for brand tint in reflections. */}
      <pointLight position={[0, -1.5, 3]} intensity={12} distance={16} decay={2} color={accentColor} />

      <Environment resolution={256} frames={1}>
        {/* Overhead softbox — the dominant, warm key. */}
        <Lightformer
          form="rect"
          intensity={5}
          color={PALETTE.rimWarm}
          scale={[12, 6, 1]}
          position={[0, 9, 2]}
          target={[0, 0, 0]}
        />
        {/* Two tall cool rim strips. */}
        <Lightformer
          form="rect"
          intensity={2.8}
          color={PALETTE.rimCool}
          scale={[1.8, 11, 1]}
          position={[-10, 3, -3]}
          target={[0, 1, 0]}
        />
        <Lightformer
          form="rect"
          intensity={2.4}
          color={PALETTE.rimCool}
          scale={[1.8, 11, 1]}
          position={[10, 3, -3]}
          target={[0, 1, 0]}
        />
        {/* Low front fill so faces / glass read from the front. */}
        <Lightformer
          form="rect"
          intensity={0.8}
          color={PALETTE.rimWarm}
          scale={[16, 2.4, 1]}
          position={[0, 0.4, 9]}
          target={[0, 2, 0]}
        />
        {/* A small accent-tinted circle for a coloured specular glint. */}
        <Lightformer
          form="circle"
          intensity={1.4}
          color={accentColor}
          scale={[3, 3, 1]}
          position={[3.5, 2.5, 5]}
          target={[0, 0, 0]}
        />
      </Environment>
    </>
  )
}
