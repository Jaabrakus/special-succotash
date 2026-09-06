"""Offline asset processing only. Never modifies the approved source WAVs or bank.

Run with NumPy/SciPy available. --check validates generated PCM and provenance;
normal mode creates deterministic derivatives and an auditable manifest. Runtime
uses imported WAVs, not this tool or SciPy. This is DSP, not a neural voice model.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy import ndimage, signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "config/weapon_audio_cleanup.json"
BANK = ROOT / "config/weapon_sound_bank.json"
OUTPUT = ROOT / "assets/audio/weapons/socom2_cleaned"
REPORT = ROOT / "artifacts/audio/weapon_cleanup_manifest.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local(resource: str) -> Path:
    assert resource.startswith("res://")
    path = (ROOT / resource[6:]).resolve()
    assert path.is_relative_to(ROOT), "resource escapes project"
    return path


def cleanup(raw: np.ndarray, rate: int, p: dict) -> tuple[np.ndarray, dict]:
    assert raw.dtype == np.int16 and raw.ndim == 1 and rate == 44100
    x = raw.astype(np.float64) / 32768.0
    # Centered RMS detects the beginning, not the loudest late reflection.
    env = np.sqrt(ndimage.uniform_filter1d(x * x, max(3, int(rate * 0.002))))
    noise_end = int(rate * p["noise_lead_seconds"])
    search_end = min(len(x), int(rate * p["onset_search_seconds"]))
    noise = max(float(np.median(env[:noise_end])), 1e-7)
    first_peak = float(env[:search_end].max())
    clean_lead = noise < first_peak * p["maximum_noise_to_peak_ratio"]
    threshold = max(noise * p["onset_noise_ratio"], first_peak * p["onset_peak_ratio"])
    candidates = np.flatnonzero(env[:search_end] >= threshold)
    # Some supplied cuts already start inside the shot. That is signal, not a
    # usable noise profile: keep its lead and bypass spectral subtraction.
    onset = int(candidates[0]) if clean_lead and candidates.size else 0
    start = max(0, onset - int(rate * p["keep_lead_seconds"]))
    protect_end = min(len(x), onset + int(rate * p["protect_attack_seconds"]))
    nfft, hop = int(p["fft_size"]), int(p["hop_size"])
    _, times, spectrum = signal.stft(x, fs=rate, window="hann", nperseg=nfft,
                                     noverlap=nfft-hop, boundary="zeros", padded=True)
    power = np.abs(spectrum) ** 2
    noise_frames = times < max(0.008, min(p["noise_lead_seconds"], (onset / rate) - 0.008))
    noise_power = np.median(power[:, noise_frames], axis=1, keepdims=True)
    floor = 10.0 ** (-p["noise_reduction_max_db"] / 20.0)
    gain = np.clip(np.sqrt(np.maximum(0.0, 1.0 - noise_power / np.maximum(power, 1e-16))), floor, 1.0)
    gain = ndimage.gaussian_filter(gain, sigma=(1.0, 1.0))
    if not clean_lead:
        gain[:] = 1.0
    _, filtered = signal.istft(spectrum * gain, fs=rate, window="hann", nperseg=nfft,
                               noverlap=nfft-hop, boundary=True)
    filtered = filtered[:len(x)]
    # Leave the transient fully original; crossfade only after protected attack.
    t = np.arange(len(x)) / rate
    wet = np.clip((t - protect_end / rate) / p["blend_seconds"], 0.0, 1.0)
    wet = wet * wet * (3.0 - 2.0 * wet)
    y = x * (1.0 - wet) + filtered * wet
    tail = np.clip((t - onset / rate - p["late_tail_start_seconds"]) /
                   (p["late_tail_end_seconds"] - p["late_tail_start_seconds"]), 0.0, 1.0)
    y *= 10.0 ** (-p["late_tail_reduction_db"] * tail / 20.0)
    y = y[start:]
    fade = int(rate * p["edge_fade_seconds"])
    y[:fade] *= np.linspace(0.0, 1.0, fade)
    y[-fade:] *= np.linspace(1.0, 0.0, fade)
    # Do not allow spectral reconstruction overshoot or normalize quieter guns.
    y = np.clip(y, -float(np.abs(x).max()), float(np.abs(x).max()))
    pcm = np.rint(y * 32768.0).clip(-32768, 32767).astype(np.int16)
    # Explicitly retain integer source samples over the attack as a hard guard.
    pcm[onset-start:protect_end-start] = raw[onset:protect_end]
    tail_begin = min(len(x)-1, onset + int(rate * p["late_tail_end_seconds"]))
    raw_tail = x[tail_begin:]
    out_tail = pcm[tail_begin-start:].astype(np.float64) / 32768.0
    tail_db = float(10 * np.log10((np.mean(out_tail**2)+1e-16)/(np.mean(raw_tail**2)+1e-16)))
    stats = {"source_frames": len(raw), "output_frames": len(pcm), "sample_rate": rate,
             "trim_frames": start, "onset_frame": onset, "protected_end_frame": protect_end,
             "spectral_cleanup_used": bool(clean_lead),
             "attack_pcm_identical": bool(np.array_equal(pcm[onset-start:protect_end-start], raw[onset:protect_end])),
             "late_tail_change_db": round(tail_db, 3),
             "source_peak": int(np.max(np.abs(raw.astype(np.int32)))),
             "output_peak": int(np.max(np.abs(pcm.astype(np.int32)))),
             "clipped_samples": int(np.count_nonzero(np.abs(pcm.astype(np.int32)) >= 32767))}
    assert stats["attack_pcm_identical"] and stats["clipped_samples"] == 0
    assert stats["output_peak"] <= stats["source_peak"]
    return pcm, stats


def run(check: bool) -> None:
    p = json.loads(PROFILE.read_text())
    bank = json.loads(BANK.read_text())
    sources = {v["source_sample_id"]: v for v in bank["weapons"].values()}
    assert len(sources) == 29
    if not check:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        REPORT.parent.mkdir(parents=True, exist_ok=True)
    previous = json.loads(REPORT.read_text()) if check else None
    report = {"schema_version": 1, "method": p["method"], "neural_ai": False,
              "profile_sha256": digest(PROFILE), "samples": {}}
    for ident, entry in sorted(sources.items()):
        src = local(entry["stream"])
        assert digest(src) == entry["sha256"], f"approved source modified: {ident}"
        rate, raw = wavfile.read(src)
        pcm, stats = cleanup(raw, rate, p)
        out = OUTPUT / f"{ident}_fire.wav"
        if check:
            out_rate, saved = wavfile.read(out)
            assert out_rate == rate and np.array_equal(saved, pcm), f"non-reproducible derivative: {ident}"
        else:
            wavfile.write(out, rate, pcm)
        stats.update({"source_stream": entry["stream"], "source_sha256": digest(src),
                      "cleaned_stream": "res://" + out.relative_to(ROOT).as_posix(), "cleaned_sha256": digest(out)})
        report["samples"][ident] = stats
        print(f"{ident}: lead -{stats['trim_frames']/rate*1000:.1f}ms; attack unchanged; late tail {stats['late_tail_change_db']:.1f}dB")
    if check:
        assert previous == report, "manifest differs from deterministic output"
    else:
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        # A/B pairs: original first, cleaned second, with silence between shots.
        for ident in ["mark_23", "ak-47", "hk5sd"]:
            _, a = wavfile.read(local(sources[ident]["stream"]))
            _, b = wavfile.read(OUTPUT / f"{ident}_fire.wav")
            pair = np.concatenate([a, np.zeros(22050, np.int16), b, np.zeros(22050, np.int16)])
            wavfile.write(REPORT.parent / f"{ident}_original_then_cleaned.wav", 44100, pair)
    print(f"WEAPON_AUDIO_CLEANUP {'CHECK' if check else 'BUILD'} PASS: {len(sources)} derivatives; originals unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    run(parser.parse_args().check)
