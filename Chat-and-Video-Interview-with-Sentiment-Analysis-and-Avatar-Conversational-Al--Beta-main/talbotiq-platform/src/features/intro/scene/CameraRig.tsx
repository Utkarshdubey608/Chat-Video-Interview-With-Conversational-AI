import { useFrame, useThree } from '@react-three/fiber'
import * as THREE from 'three'

import type { IntroCamProxy, ScalarRef } from '../contract'

const tmpLook = new THREE.Vector3()

/**
 * Applies the camera proxy to the live R3F camera every frame. The timeline
 * owns the dramatic move (dolly / push-pull / FOV); this rig layers a subtle,
 * time-driven handheld float + parallax on top and applies the dutch roll, so
 * no move is ever perfectly linear/mechanical.
 */
export function CameraRig({ cam, time }: { cam: IntroCamProxy; time: ScalarRef }) {
  const camera = useThree((s) => s.camera)

  useFrame(() => {
    const t = time.value
    const f = cam.float.value

    // Layered sines → organic handheld drift; amplitude scales with `float`.
    const ox = (Math.sin(t * 0.42) * 0.18 + Math.sin(t * 1.13) * 0.05) * f
    const oy = (Math.cos(t * 0.37) * 0.12 + Math.sin(t * 0.91) * 0.04) * f
    const oz = Math.sin(t * 0.29) * 0.1 * f

    camera.position.set(cam.position.x + ox, cam.position.y + oy, cam.position.z + oz)
    tmpLook.copy(cam.lookAt)
    camera.lookAt(tmpLook)
    if (cam.dutch.value !== 0) {
      camera.rotateZ(cam.dutch.value)
    }

    const persp = camera as THREE.PerspectiveCamera
    if (persp.isPerspectiveCamera && persp.fov !== cam.fov.value) {
      persp.fov = cam.fov.value
      persp.updateProjectionMatrix()
    }
  })

  return null
}
