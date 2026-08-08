extends SceneTree

## Synthétise les nappes d'ambiance de la caverne. Lancer via :
##   godot --headless --path godot --script tools/build_ambience_audio.gd
##
## ## Pourquoi de l'audio écrit en code
##
## Le jeu est sous licence propriétaire (cf `LICENSE`). Toute banque de sons
## tierce impose sa propre licence, et une nappe d'ambiance sous CC-BY
## obligerait à créditer un tiers dans un projet qui se veut entièrement
## possédé. Synthétiser ici règle la question à la racine : ces fichiers
## n'ont pas d'auteur extérieur, et ils sont **reproductibles** — le son n'est
## pas un binaire opaque dans LFS, c'est ce script.
##
## ## Ce que ça vaut, et ce que ça ne vaut pas
##
## Ce sont des nappes : du souffle, un grondement, un scintillement. Elles
## portent l'espace et le silence, ce qui est exactement le rôle d'une
## ambiance de caverne. Elles ne remplacent pas des sons d'action — impacts,
## tirs, voix du boss — qui demandent une attaque nette et un caractère que la
## synthèse additive ne donne pas. Ceux-là restent à produire.
##
## ## Chaque son a une source visible
##
## Rien n'est diffusé « de partout ». Le vent sort des puits de voûte, le
## scintillement vient des cristaux, le clapot vient du lac. C'est ce qui
## permet à l'oreille de servir de boussole quand la brume coupe la vue —
## la mécanique signature du niveau.

const OUTPUT_DIR := "res://assets/audio/ambience"
const MIX_RATE: int = 22050

## Graine fixe : deux exécutions doivent donner exactement les mêmes octets,
## sinon chaque lancement de ce script produirait un diff dans le dépôt.
const SEED: int = 20260808


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var written: int = 0
	written += _save("cave_drone", _cave_drone())
	written += _save("wind_shaft", _wind_shaft())
	written += _save("crystal_shimmer", _crystal_shimmer())
	written += _save("water_lap", _water_lap())

	print("[ambiance] %d nappes écrites dans %s" % [written, OUTPUT_DIR])
	quit(0 if written == 4 else 1)


# ---------------------------------------------------------------------------
# Les nappes
# ---------------------------------------------------------------------------

## Le grondement de la roche. Très bas, très lent : c'est le silence de la
## caverne qui a une couleur, pas un son qu'on remarque.
func _cave_drone() -> PackedFloat32Array:
	var seconds: float = 12.0
	var n: int = int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# Trois partiels très graves, choisis pour que leurs battements se
	# rejouent à l'identique au bouclage : les périodes divisent la durée.
	var partials: Array[float] = [36.0, 54.0, 91.0]
	for i in n:
		var t: float = float(i) / float(MIX_RATE)
		var v: float = 0.0
		for k in partials.size():
			var f: float = _loopable(partials[k], seconds)
			v += sin(TAU * f * t) * (0.5 / float(k + 1))
		# Une respiration très lente, elle aussi bouclable.
		var breath: float = 0.75 + 0.25 * sin(TAU * _loopable(0.08, seconds) * t)
		out[i] = v * 0.22 * breath
	return out


## Le vent des puits de voûte. Bruit filtré passe-bas, avec des rafales
## lentes : il vient de l'extérieur, donc il est la seule chose du niveau qui
## rappelle qu'il existe un dehors.
func _wind_shaft() -> PackedFloat32Array:
	var seconds: float = 16.0
	var n: int = int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Deux pôles en cascade : un seul filtre laisse un souffle trop sifflant.
	var lp1: float = 0.0
	var lp2: float = 0.0
	const ALPHA: float = 0.035
	for i in n:
		var white: float = rng.randf_range(-1.0, 1.0)
		lp1 += (white - lp1) * ALPHA
		lp2 += (lp1 - lp2) * ALPHA
		var t: float = float(i) / float(MIX_RATE)
		var gust: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(TAU * _loopable(0.07, seconds) * t))
		gust *= 0.8 + 0.2 * sin(TAU * _loopable(0.19, seconds) * t)
		out[i] = lp2 * 5.5 * gust
	_crossfade_ends(out, int(0.6 * MIX_RATE))
	return out


## Le scintillement des cristaux. Aigu, ténu, jamais fixe : il doit se
## remarquer quand on approche et disparaître dès qu'on s'éloigne.
func _crystal_shimmer() -> PackedFloat32Array:
	var seconds: float = 9.0
	var n: int = int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials: Array[float] = [880.0, 1320.0, 1760.0, 2640.0]
	for i in n:
		var t: float = float(i) / float(MIX_RATE)
		var v: float = 0.0
		for k in partials.size():
			var f: float = _loopable(partials[k], seconds)
			# Chaque partiel a sa propre pulsation : l'ensemble ne se répète
			# qu'au bout du fichier, l'oreille n'entend pas la boucle.
			var puls: float = 0.5 + 0.5 * sin(TAU * _loopable(0.11 + 0.037 * float(k), seconds) * t)
			v += sin(TAU * f * t) * puls / float(k + 2)
		out[i] = v * 0.09
	return out


## Le clapot du lac. Bruit filtré bande étroite, modulé — assez pour situer
## l'eau à l'oreille, pas assez pour devenir une vague de bord de mer.
func _water_lap() -> PackedFloat32Array:
	var seconds: float = 10.0
	var n: int = int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var lp: float = 0.0
	var hp_prev: float = 0.0
	var hp: float = 0.0
	for i in n:
		var white: float = rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.12
		# Passe-haut par différence : retire le grave, qui appartient au drone.
		hp = 0.92 * (hp + lp - hp_prev)
		hp_prev = lp
		var t: float = float(i) / float(MIX_RATE)
		var swell: float = 0.35 + 0.65 * absf(sin(TAU * _loopable(0.33, seconds) * t))
		out[i] = hp * 0.9 * swell
	_crossfade_ends(out, int(0.5 * MIX_RATE))
	return out


# ---------------------------------------------------------------------------
# Outillage
# ---------------------------------------------------------------------------

## Arrondit une fréquence pour qu'elle tienne un nombre ENTIER de cycles dans
## la durée du fichier. Sans ça, la fin ne raccorde pas au début et la boucle
## claque à chaque tour — le défaut le plus audible d'une ambiance bouclée.
func _loopable(frequency: float, seconds: float) -> float:
	var cycles: float = maxf(1.0, roundf(frequency * seconds))
	return cycles / seconds


## Pour les nappes bruitées, aucune fréquence ne raccorde : on fond la fin sur
## le début.
func _crossfade_ends(samples: PackedFloat32Array, fade: int) -> void:
	var n: int = samples.size()
	if fade <= 0 or fade * 2 >= n:
		return
	for i in fade:
		var t: float = float(i) / float(fade)
		samples[i] = lerpf(samples[n - fade + i], samples[i], t)


func _save(name: String, samples: PackedFloat32Array) -> int:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples.size()
	stream.data = _to_pcm16(samples)

	var path: String = "%s/%s.tres" % [OUTPUT_DIR, name]
	if ResourceSaver.save(stream, path) != OK:
		push_error("[ambiance] échec d'écriture : %s" % path)
		return 0
	print("[ambiance] %s — %.1f s, %d échantillons" % [name, float(samples.size()) / MIX_RATE, samples.size()])
	return 1


## Normalise puis convertit en PCM 16 bits little-endian. La normalisation est
## indispensable : les nappes ont des amplitudes très différentes selon leur
## méthode de synthèse, et c'est le mixage — pas la synthèse — qui doit
## décider de leur niveau relatif.
func _to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var peak: float = 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain: float = 0.85 / maxf(peak, 0.0001)

	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = clampi(int(roundf(samples[i] * gain * 32767.0)), -32768, 32767)
		if v < 0:
			v += 65536
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	return bytes
