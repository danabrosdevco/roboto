#!/usr/bin/env bash
# Acoustic feature extraction with no dependencies beyond od/awk/grep — python
# is a Store stub here, and there is no ffmpeg or sox.
#
# The library is 24-bit stereo PCM at 48kHz, so samples are reconstructed from
# raw bytes: little-endian 3-byte signed, left channel only (interleaved stereo
# would double-count zero crossings at the channel boundary).
#
# Per file:
#   dur_s    exact, from the data chunk size and the fmt header
#   rms      loudness of the analysis window, normalised 0..1
#   peak     max absolute sample, normalised 0..1
#   zcr_hz   zero crossings per second. A proxy for brightness/pitch that needs
#            no FFT: chirps and beeps cross often, growls and rumbles rarely.
#   silence  fraction of the window below -30dBFS, which separates a short blip
#            padded with air from a continuous utterance.

set -uo pipefail
DIR="${1:?usage: analyze_wavs.sh <dir>}"

printf "file\tdur_s\trate\tch\tbits\trms\tpeak\tzcr_hz\tsilence\n"

for f in "$DIR"/*.wav; do
	[ -f "$f" ] || continue
	name=$(basename "$f")

	fmt_off=$(head -c 512 "$f" | grep -abo "fmt " | head -1 | cut -d: -f1)
	data_off=$(head -c 512 "$f" | grep -abo "data" | head -1 | cut -d: -f1)
	if [ -z "$fmt_off" ] || [ -z "$data_off" ]; then
		printf "%s\tPARSE_FAIL\n" "$name"; continue
	fi

	channels=$(od -An -tu2 -v -j $((fmt_off + 10)) -N 2 "$f" | tr -d ' ')
	rate=$(od -An -tu4 -v -j $((fmt_off + 12)) -N 4 "$f" | tr -d ' ')
	bits=$(od -An -tu2 -v -j $((fmt_off + 22)) -N 2 "$f" | tr -d ' ')
	dsize=$(od -An -tu4 -v -j $((data_off + 4)) -N 4 "$f" | tr -d ' ')
	dstart=$((data_off + 8))

	if [ -z "$rate" ] || [ "$rate" -eq 0 ]; then
		printf "%s\tPARSE_FAIL\n" "$name"; continue
	fi

	bpf=$((channels * bits / 8))
	dur=$(awk -v d="$dsize" -v b="$bpf" -v r="$rate" 'BEGIN{printf "%.3f", d/(b*r)}')

	# Window: start a seventh of the way in to skip leading silence, cap at
	# ~0.2s. Enough for stable ZCR/RMS without pushing 50MB through od.
	win=60000
	skip=$((dsize / 7))
	skip=$((skip - skip % bpf))
	[ $((skip + win)) -gt "$dsize" ] && win=$((dsize - skip))
	[ "$win" -lt 3000 ] && { skip=0; win=$dsize; }

	od -An -tu1 -v -j $((dstart + skip)) -N "$win" "$f" \
	| awk -v name="$name" -v dur="$dur" -v r="$rate" -v c="$channels" \
	      -v bits="$bits" -v bpf="$bpf" '
		BEGIN { FULL = 8388608; QUIET = FULL * 0.031 }
		{
			for (i = 1; i <= NF; i++) {
				pos = bidx % bpf
				b = $i + 0
				if (pos == 0) t0 = b
				else if (pos == 1) t1 = b
				else if (pos == 2) {
					v = t0 + t1 * 256 + b * 65536
					if (v >= FULL) v -= 2 * FULL
					n++
					sum2 += v * v
					a = (v < 0 ? -v : v)
					if (a > peak) peak = a
					if (a < QUIET) quiet++
					if (n > 1 && ((v >= 0 && prev < 0) || (v < 0 && prev >= 0))) cross++
					prev = v
				}
				bidx++
			}
		}
		END {
			if (n < 2) { printf "%s\t%s\t%d\t%d\t%d\tEMPTY\n", name, dur, r, c, bits; exit }
			rms = sqrt(sum2 / n) / FULL
			zcr = cross / (n / r)
			printf "%s\t%s\t%d\t%d\t%d\t%.4f\t%.4f\t%.1f\t%.3f\n",
				name, dur, r, c, bits, rms, peak / FULL, zcr, quiet / n
		}
	'
done
