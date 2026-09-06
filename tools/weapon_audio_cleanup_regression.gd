extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/audio/weapon_cleanup_manifest.json"))
	_expect(report.profile_sha256 == FileAccess.get_sha256("res://config/weapon_audio_cleanup.json"), "profile matches derived assets")
	_expect(not bool(report.neural_ai), "DSP provenance is honest")
	_expect(report.samples.size() == 29, "all 29 source samples covered")
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_sound_bank.json"))
	_expect(bool(bank.get("use_cleaned_streams", false)), "cleaned sources enabled")
	for id: String in report.samples:
		var sample: Dictionary = report.samples[id]
		_expect(FileAccess.get_sha256(sample.source_stream) == sample.source_sha256, id + " original unchanged")
		_expect(FileAccess.get_sha256(sample.cleaned_stream) == sample.cleaned_sha256, id + " derivative matches report")
		_check_pcm(id, sample)
	for entry: Dictionary in bank.weapons.values():
		var sample: Dictionary = report.samples[entry.source_sample_id]
		_expect(entry.cleaned_stream == sample.cleaned_stream and entry.cleaned_sha256 == sample.cleaned_sha256, "runtime bank selects checked derivative")
	print("WEAPON_AUDIO_CLEANUP_REGRESSION ", "PASS" if failures == 0 else "FAIL", " samples=29 failures=", failures)
	quit(0 if failures == 0 else 1)

func _check_pcm(id: String, sample: Dictionary) -> void:
	# Load the approved PCM without the source's existing lossy import settings.
	var original := AudioStreamWAV.load_from_file(sample.source_stream, {"compress/mode": 0})
	var cleaned := load(String(sample.cleaned_stream)) as AudioStreamWAV
	_expect(original != null and cleaned != null, id + " resources load")
	if original == null or cleaned == null:
		return
	_expect(cleaned.format == AudioStreamWAV.FORMAT_16_BITS, id + " no additional lossy encoding")
	_expect(cleaned.mix_rate == 44100 and not cleaned.stereo and cleaned.loop_mode == AudioStreamWAV.LOOP_DISABLED, id + " mono 44.1k nonlooping")
	var onset := int(sample.onset_frame)
	var trim := int(sample.trim_frames)
	var end := int(sample.protected_end_frame)
	var before := original.data
	var after := cleaned.data
	_expect(after.size() == int(sample.output_frames) * 2, id + " expected PCM size")
	_expect(before.slice(onset * 2, end * 2) == after.slice((onset-trim) * 2, (end-trim) * 2), id + " imported attack is bit-identical")
	_expect(int(sample.clipped_samples) == 0 and int(sample.output_peak) <= int(sample.source_peak), id + " no clipping or normalization")
	_expect(trim >= 0 and trim <= int(0.14 * 44100), id + " bounded lead removal")
	_expect(float(sample.late_tail_change_db) <= 0.01, id + " no louder source tail")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("WEAPON_AUDIO_CLEANUP_FAIL " + label)
