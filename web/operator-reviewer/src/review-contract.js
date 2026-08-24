export const REVIEW_SCHEMA_VERSION = 1;
export const REVIEW_KIND = "socom141.animation_review";
export const ALLOWED_EVENT_TYPES = Object.freeze([
  "FOOT_PLANT_LEFT",
  "FOOT_PLANT_RIGHT",
  "MAGAZINE_REMOVED",
  "MAGAZINE_INSERTED",
  "GRENADE_RELEASED",
  "ACTION_RECOVERY",
  "CUSTOM",
]);

const isFiniteNumber = (value) => typeof value === "number" && Number.isFinite(value);

export function createReviewContract({
  assetPath,
  assetName,
  clipName,
  durationSeconds,
  markers = [],
  boneCount = 0,
}) {
  const duration = Math.max(0, Number(durationSeconds) || 0);
  const normalizedMarkers = markers
    .map((marker, index) => ({
      id: String(marker.id || `marker-${index + 1}`),
      type: ALLOWED_EVENT_TYPES.includes(marker.type) ? marker.type : "CUSTOM",
      time_seconds: Math.min(duration, Math.max(0, Number(marker.time_seconds) || 0)),
      bone: marker.bone ? String(marker.bone) : "",
      note: marker.note ? String(marker.note) : "",
    }))
    .sort((left, right) => left.time_seconds - right.time_seconds);

  return {
    schema_version: REVIEW_SCHEMA_VERSION,
    kind: REVIEW_KIND,
    review_only: true,
    apply_to_gameplay: false,
    authority: "godot",
    source: {
      asset_path: String(assetPath || "local://unsaved-review-asset"),
      asset_name: String(assetName || "Unnamed operator asset"),
      clip_name: String(clipName || "NO_ANIMATION"),
      duration_seconds: duration,
      bone_count: Math.max(0, Math.trunc(Number(boneCount) || 0)),
    },
    markers: normalizedMarkers,
    authored_changes: [],
    created_at_utc: new Date().toISOString(),
  };
}

export function validateReviewContract(document) {
  const errors = [];
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    return { valid: false, errors: ["Review document must be an object."] };
  }
  if (document.schema_version !== REVIEW_SCHEMA_VERSION) {
    errors.push(`schema_version must be ${REVIEW_SCHEMA_VERSION}.`);
  }
  if (document.kind !== REVIEW_KIND) {
    errors.push(`kind must be ${REVIEW_KIND}.`);
  }
  if (document.review_only !== true || document.apply_to_gameplay !== false) {
    errors.push("Review documents cannot request gameplay application.");
  }
  if (document.authority !== "godot") {
    errors.push("Godot must remain the authority.");
  }
  if (!document.source || typeof document.source !== "object") {
    errors.push("source is required.");
  } else {
    if (typeof document.source.asset_path !== "string" || !document.source.asset_path) {
      errors.push("source.asset_path is required.");
    }
    if (typeof document.source.clip_name !== "string" || !document.source.clip_name) {
      errors.push("source.clip_name is required.");
    }
    if (!isFiniteNumber(document.source.duration_seconds) || document.source.duration_seconds < 0) {
      errors.push("source.duration_seconds must be a non-negative number.");
    }
  }
  if (!Array.isArray(document.markers)) {
    errors.push("markers must be an array.");
  } else {
    document.markers.forEach((marker, index) => {
      const prefix = `markers[${index}]`;
      if (!marker || typeof marker !== "object") {
        errors.push(`${prefix} must be an object.`);
        return;
      }
      if (!ALLOWED_EVENT_TYPES.includes(marker.type)) {
        errors.push(`${prefix}.type is not allowed.`);
      }
      if (!isFiniteNumber(marker.time_seconds) || marker.time_seconds < 0) {
        errors.push(`${prefix}.time_seconds must be non-negative.`);
      } else if (
        document.source &&
        isFiniteNumber(document.source.duration_seconds) &&
        marker.time_seconds > document.source.duration_seconds + 0.0001
      ) {
        errors.push(`${prefix}.time_seconds exceeds the clip duration.`);
      }
    });
  }
  if (!Array.isArray(document.authored_changes) || document.authored_changes.length !== 0) {
    errors.push("The read-only reviewer must export an empty authored_changes array.");
  }
  return { valid: errors.length === 0, errors };
}
