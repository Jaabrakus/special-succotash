export const PORT_CONTRACT_VERSION = 1;

export const CAMERA = Object.freeze({
  distance: 2.2,
  height: 2.05,
  lookHeight: 1.45,
  fov: 68,
  near: 0.08,
  sensitivity: 0.0024,
  pitchMin: -60,
  pitchMax: 28,
  collisionRadius: 0.12,
});

export const MOVEMENT = Object.freeze({
  moveSpeed: 6.5,
  strafeSpeed: 6.5,
  crouchSpeed: 2.6,
  proneSpeed: 1.25,
  acceleration: 45,
  brakingAcceleration: 60,
  reversalAcceleration: 90,
  gravity: 22,
  jumpVelocity: 6.2,
  diveSpeed: 7.6,
  diveDuration: 0.72,
  playerRadius: 0.34,
});

export const WEAPON = Object.freeze({
  magazineCapacity: 30,
  reserveAmmo: 211,
  damage: 34,
  headshotMultiplier: 3.5,
  fireRateRpm: 435,
  reloadSeconds: 1.75,
  baseSpreadDeg: 0.32,
  movingSpreadDeg: 0.95,
  fullGaitSpreadDeg: 1.45,
  bloomPerShotDeg: 0.42,
  maxBloomDeg: 1.45,
  crouchBloomPerShotDeg: 0.3,
  crouchMaxBloomDeg: 1,
  bloomRecoveryDegPerSecond: 14,
  reticleBaseGapPx: 5,
  reticleMaxGapPx: 46,
  reticleResponse: 18.5,
});

export const GRENADE = Object.freeze({
  count: 3,
  fuseSeconds: 3,
  restitution: 0.38,
  chargeSeconds: 0.78,
  minimumSpeed: 9,
  maximumSpeed: 16,
  minimumElevationDeg: -8,
  maximumElevationDeg: 68,
  blastRadius: 7,
  maximumDamage: 120,
  radius: 0.055,
});
