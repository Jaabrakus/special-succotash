export function moveToward(current, target, maximumDelta) {
  if (current < target) return Math.min(current + maximumDelta, target);
  return Math.max(current - maximumDelta, target);
}

export function recoverBloom(current, recoveryPerSecond, deltaSeconds) {
  return Math.max(0, current - recoveryPerSecond * Math.max(0, deltaSeconds));
}

export function bloomAfterShot(current, crouched, weapon) {
  const gain = crouched ? weapon.crouchBloomPerShotDeg : weapon.bloomPerShotDeg;
  const maximum = crouched ? weapon.crouchMaxBloomDeg : weapon.maxBloomDeg;
  return Math.min(maximum, current + gain);
}

export function spreadDegrees({ speedRatio, crouched, bloom }, weapon) {
  const movementSpread = weapon.movingSpreadDeg +
    (weapon.fullGaitSpreadDeg - weapon.movingSpreadDeg) * Math.min(1, Math.max(0, speedRatio));
  const base = crouched ? weapon.baseSpreadDeg * 0.72 : weapon.baseSpreadDeg;
  return Math.max(base, speedRatio > 0.04 ? movementSpread : base) + bloom;
}

export function grenadeSpeed(chargeRatio, grenade) {
  const amount = Math.min(1, Math.max(0, chargeRatio));
  return grenade.minimumSpeed + (grenade.maximumSpeed - grenade.minimumSpeed) * amount;
}

export function blastDamage(distance, grenade) {
  if (distance >= grenade.blastRadius) return 0;
  return grenade.maximumDamage * (1 - distance / grenade.blastRadius);
}

export function resolveAxis(position, radius, boxes, axis) {
  let value = position[axis];
  const otherAxis = axis === "x" ? "z" : "x";
  for (const box of boxes) {
    const insideOther = position[otherAxis] > box.min[otherAxis] - radius &&
      position[otherAxis] < box.max[otherAxis] + radius;
    if (!insideOther) continue;
    const minimum = box.min[axis] - radius;
    const maximum = box.max[axis] + radius;
    if (value > minimum && value < maximum) {
      value = Math.abs(value - minimum) < Math.abs(value - maximum) ? minimum : maximum;
    }
  }
  return value;
}
