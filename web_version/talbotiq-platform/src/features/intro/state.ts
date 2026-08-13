import * as THREE from 'three'

import { CAMERA, DOF, POST } from './constants'
import { scalar, type IntroCamProxy, type IntroFxProxy, type IntroRefs } from './contract'

/** The full set of mutable proxies the film animates. Created once, owned by
 *  IntroCanvas, shared by every scene node and the timeline orchestrator. */
export type IntroState = { cam: IntroCamProxy; fx: IntroFxProxy; refs: IntroRefs }

/** Builds frame-zero state (open pose, cloud full, hero hidden). */
export function createIntroState(): IntroState {
  const cam: IntroCamProxy = {
    position: new THREE.Vector3(...CAMERA.rush.position),
    lookAt: new THREE.Vector3(...CAMERA.rush.lookAt),
    fov: scalar(CAMERA.rush.fov),
    float: scalar(0),
    dutch: scalar(0),
  }
  const fx: IntroFxProxy = {
    bloom: scalar(POST.bloomRest),
    focusDistance: scalar(DOF.rushFocus),
    bokeh: scalar(DOF.rushBokeh),
    aberration: scalar(POST.aberrationRest),
  }
  const refs: IntroRefs = {
    world: { time: scalar(0), timeScale: scalar(1) },
    rush: scalar(0),
    morph: scalar(0),
    cloud: scalar(1),
    heroReveal: scalar(0),
    heroGlow: scalar(0),
    lightSweep: scalar(0),
    flare: scalar(0),
  }
  return { cam, fx, refs }
}
