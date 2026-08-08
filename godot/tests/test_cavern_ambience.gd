extends SceneTree

## Ambiance sonore et post-process (E7 #31). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_ambience.gd
##
## Ce qui casserait sans bruit :
##
## 1. **Une nappe absente.** `load()` d'un `.tres` manquant renvoie `null`, et
##    le code se contente de ne rien poser. Le niveau serait simplement
##    silencieux — et rien, jamais, ne le dirait.
## 2. **Des nappes qui ne bouclent pas.** Une ambiance qui s'arrête après
##    douze secondes laisse un vide qu'on met un moment à s'expliquer.
## 3. **Le glow éteint.** C'est la passe qui porte l'identité du niveau :
##    sans elle, les cristaux émissifs redeviennent des aplats clairs. Un
##    `.tres` régénéré sans glow rendrait la caverne fade sans erreur.

const ENVIRONMENT_PATH := "res://data/levels/level01_cavern_environment.tres"
const AMBIENCE_DIR := "res://assets/audio/ambience"
const NAPPES: Array[String] = ["cave_drone", "wind_shaft", "crystal_shimmer", "water_lap"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	failed += _test_every_ambience_layer_exists_and_loops()
	failed += _test_the_glow_is_on()
	failed += _test_relief_reading_helpers_are_on()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la caverne a du son et du relief")
		quit(0)


func _test_every_ambience_layer_exists_and_loops() -> int:
	for name in NAPPES:
		var path: String = "%s/%s.tres" % [AMBIENCE_DIR, name]
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		if stream == null:
			print("[FAIL] nappe « %s » absente — lancer tools/build_ambience_audio.gd" % name)
			return 1
		if stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			print("[FAIL] nappe « %s » ne boucle pas — l'ambiance s'arrêterait" % name)
			return 1
		if stream.data.size() < 2:
			print("[FAIL] nappe « %s » est vide" % name)
			return 1
		# Un fichier muet passerait tous les tests précédents.
		if _peak(stream) < 0.05:
			print("[FAIL] nappe « %s » est silencieuse (crête %.3f)" % [name, _peak(stream)])
			return 1
	print("[OK] every_ambience_layer_exists_and_loops (%d nappes)" % NAPPES.size())
	return 0


func _test_the_glow_is_on() -> int:
	var env: Environment = load(ENVIRONMENT_PATH) as Environment
	if env == null:
		print("[FAIL] environnement introuvable : %s" % ENVIRONMENT_PATH)
		return 1
	if not env.glow_enabled:
		print("[FAIL] glow éteint — les cristaux émissifs redeviennent des aplats")
		return 1
	if env.glow_intensity <= 0.0:
		print("[FAIL] glow à intensité nulle : activé mais sans effet")
		return 1
	# Un halo large, pas un néon : au moins un niveau haut doit contribuer.
	var wide: float = env.get_glow_level(3) + env.get_glow_level(4)
	if wide <= 0.0:
		print("[FAIL] glow : seuls les niveaux fins contribuent — halo « néon »")
		return 1
	print("[OK] the_glow_is_on (intensité %.2f, niveaux larges %.1f)"
		% [env.glow_intensity, wide])
	return 0


func _test_relief_reading_helpers_are_on() -> int:
	var env: Environment = load(ENVIRONMENT_PATH) as Environment
	if not env.ssao_enabled:
		print("[FAIL] SSAO éteint — sol et paroi se rejoignent en dégradé mou")
		return 1
	if not env.adjustment_enabled:
		print("[FAIL] ajustements éteints — l'inflexion glaciaire est perdue")
		return 1
	if env.adjustment_saturation >= 1.0:
		print("[FAIL] saturation à %.2f — l'art bible demande « froid, très désaturé »"
			% env.adjustment_saturation)
		return 1
	print("[OK] relief_reading_helpers_are_on (SSAO r=%.1f, saturation %.2f)"
		% [env.ssao_radius, env.adjustment_saturation])
	return 0


## Crête absolue du signal, lue directement dans le PCM 16 bits.
func _peak(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var peak: int = 0
	# Un échantillon sur 64 : la crête d'une nappe ne se cache pas.
	var i: int = 0
	while i + 1 < data.size():
		var v: int = data[i] | (data[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		peak = maxi(peak, absi(v))
		i += 128
	return float(peak) / 32767.0
