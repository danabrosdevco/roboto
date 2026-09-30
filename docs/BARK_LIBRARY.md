# Droid voice library — acoustic sort

105 clips in `sounds/sfx/Robot Droid Voices/`, all 24-bit stereo PCM at 48kHz.
Before this, **3 of them were in use** (`WAV_RDV__2`, `__5`, `__98`) and the
other 102 had never been heard.

## How these were sorted

No ffmpeg, sox or working python on this machine, so features were extracted by
parsing the WAV headers and reconstructing 24-bit samples from raw bytes
(`tools/analyze_wavs.sh`):

- **dur** — exact, from the data chunk size and the fmt header.
- **zcr** — zero crossings per second. A proxy for brightness/pitch that needs
  no FFT: chirps and squeals cross often, growls and rumbles rarely.
- **sil** — fraction of the analysis window below -30dBFS. Separates a short
  blip padded with air from a continuous utterance.

**This is an acoustic sort, not a semantic one.** I can tell a short bright
chirp from a long low moan; I cannot tell "affirmative" from "alarmed". The
buckets exist so you audition 14 candidates for a role instead of 105, and so
the starting assignment in `bark_set_droid.tres` is plausible rather than
random.

Distribution: dur 0.69–12.4s (median 2.27), zcr 701–11770Hz (median 3178),
silence 7%–99%.

## Buckets and what each suits

| Bucket | n | Character | Suggested line |
|---|---|---|---|
| `1_chirp_short` | 14 | under 1.5s, bright | **ORDER_ACK** — must be short; you hear it constantly |
| `2_blip_short` | 9 | under 1.5s, darker | **RELOAD** (enemies), short mechanical |
| `3_alert_bright` | 8 | 1.5–2.5s, bright | **CONTACT** — urgency reads as brightness |
| `4_call_mid` | 18 | 1.5–2.5s, mid | **KILL** and **SEARCH** |
| `5_growl_low` | 21 | zcr under 2100, dark | **HURT** — the biggest bucket, and it should be, it's the most frequent line |
| `6_wail_bright` | 5 | long, bright | **CONTACT** overflow, or alarms |
| `7_moan_long` | 17 | long, mid/dark | **DOWNED** — a descending, drawn-out line |
| `REVIEW_quiet` | 9 | rms under 0.02 **or** over 80% silence | Audition before use — several may be near-empty files |
| `REVIEW_long` | 4 | over 6s | Too long for a bark. Likely alarms or ambient loops |

The two REVIEW buckets are 13 clips I would not ship without listening. One file
is 99% silence and one is 12.4 seconds, which is not a bark by any definition.

---

## 1_chirp_short

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__10.wav` | 1.19s | 4795 | 39% |
| `WAV_RDV__105.wav` | 1.20s | 5798 | 43% |
| `WAV_RDV__18.wav` | 1.06s | 5141 | 79% |
| `WAV_RDV__19.wav` | 1.47s | 4642 | 36% |
| `WAV_RDV__27.wav` | 1.30s | 4862 | 37% |
| `WAV_RDV__28.wav` | 1.43s | 4786 | 68% |
| `WAV_RDV__33.wav` | 0.69s | 8064 | 67% |
| `WAV_RDV__34.wav` | 1.21s | 4368 | 57% |
| `WAV_RDV__36.wav` | 0.91s | 4973 | 33% |
| `WAV_RDV__37.wav` | 0.69s | 6499 | 56% |
| `WAV_RDV__40.wav` | 1.18s | 6432 | 56% |
| `WAV_RDV__6.wav` | 1.47s | 6758 | 64% |
| `WAV_RDV__7.wav` | 0.85s | 5544 | 50% |
| `WAV_RDV__9.wav` | 1.46s | 5405 | 51% |

## 2_blip_short

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__104.wav` | 1.40s | 1733 | 11% |
| `WAV_RDV__12.wav` | 1.07s | 3149 | 26% |
| `WAV_RDV__2.wav` | 1.20s | 3643 | 22% |
| `WAV_RDV__24.wav` | 1.17s | 2333 | 15% |
| `WAV_RDV__31.wav` | 1.32s | 1930 | 32% |
| `WAV_RDV__35.wav` | 1.03s | 3533 | 31% |
| `WAV_RDV__38.wav` | 1.33s | 3374 | 19% |
| `WAV_RDV__54.wav` | 0.90s | 2054 | 18% |
| `WAV_RDV__72.wav` | 1.40s | 3384 | 23% |

## 3_alert_bright

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__101.wav` | 1.70s | 4430 | 48% |
| `WAV_RDV__102.wav` | 1.70s | 4205 | 33% |
| `WAV_RDV__17.wav` | 1.83s | 5419 | 35% |
| `WAV_RDV__22.wav` | 1.57s | 4618 | 30% |
| `WAV_RDV__25.wav` | 1.87s | 5453 | 50% |
| `WAV_RDV__32.wav` | 1.83s | 5136 | 61% |
| `WAV_RDV__73.wav` | 1.53s | 5242 | 39% |
| `WAV_RDV__90.wav` | 2.17s | 4973 | 33% |

## 4_call_mid

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__1.wav` | 1.89s | 2928 | 15% |
| `WAV_RDV__103.wav` | 2.27s | 3739 | 26% |
| `WAV_RDV__11.wav` | 1.55s | 2448 | 57% |
| `WAV_RDV__13.wav` | 1.97s | 2395 | 17% |
| `WAV_RDV__20.wav` | 2.20s | 4094 | 45% |
| `WAV_RDV__30.wav` | 2.22s | 3917 | 59% |
| `WAV_RDV__42.wav` | 1.67s | 3317 | 12% |
| `WAV_RDV__5.wav` | 1.61s | 2328 | 7% |
| `WAV_RDV__51.wav` | 2.46s | 3667 | 39% |
| `WAV_RDV__52.wav` | 2.27s | 3326 | 52% |
| `WAV_RDV__56.wav` | 2.31s | 3086 | 19% |
| `WAV_RDV__60.wav` | 1.97s | 2194 | 12% |
| `WAV_RDV__62.wav` | 2.23s | 2232 | 12% |
| `WAV_RDV__68.wav` | 2.20s | 3514 | 36% |
| `WAV_RDV__78.wav` | 2.20s | 2285 | 21% |
| `WAV_RDV__8.wav` | 1.98s | 3758 | 29% |
| `WAV_RDV__81.wav` | 2.40s | 2731 | 17% |
| `WAV_RDV__83.wav` | 2.30s | 3158 | 18% |

## 5_growl_low

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__100.wav` | 2.33s | 1954 | 11% |
| `WAV_RDV__14.wav` | 2.34s | 1805 | 26% |
| `WAV_RDV__21.wav` | 1.50s | 878 | 30% |
| `WAV_RDV__26.wav` | 1.53s | 1954 | 78% |
| `WAV_RDV__29.wav` | 1.83s | 840 | 24% |
| `WAV_RDV__45.wav` | 2.84s | 1037 | 11% |
| `WAV_RDV__46.wav` | 2.13s | 931 | 8% |
| `WAV_RDV__48.wav` | 3.61s | 1675 | 16% |
| `WAV_RDV__50.wav` | 3.33s | 1493 | 24% |
| `WAV_RDV__57.wav` | 5.55s | 1186 | 10% |
| `WAV_RDV__58.wav` | 3.53s | 1421 | 13% |
| `WAV_RDV__59.wav` | 2.43s | 2093 | 9% |
| `WAV_RDV__61.wav` | 5.67s | 1944 | 10% |
| `WAV_RDV__63.wav` | 4.43s | 1992 | 14% |
| `WAV_RDV__67.wav` | 2.37s | 1536 | 10% |
| `WAV_RDV__74.wav` | 2.27s | 1138 | 11% |
| `WAV_RDV__82.wav` | 3.17s | 840 | 11% |
| `WAV_RDV__84.wav` | 4.10s | 1512 | 10% |
| `WAV_RDV__89.wav` | 2.60s | 1987 | 15% |
| `WAV_RDV__92.wav` | 3.30s | 1661 | 9% |
| `WAV_RDV__98.wav` | 2.17s | 1843 | 13% |

## 6_wail_bright

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__15.wav` | 2.64s | 5448 | 31% |
| `WAV_RDV__76.wav` | 2.70s | 7238 | 64% |
| `WAV_RDV__80.wav` | 3.03s | 6000 | 51% |
| `WAV_RDV__86.wav` | 2.70s | 5530 | 43% |
| `WAV_RDV__87.wav` | 2.90s | 4642 | 44% |

## 7_moan_long

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__3.wav` | 3.13s | 3485 | 26% |
| `WAV_RDV__47.wav` | 3.53s | 2602 | 20% |
| `WAV_RDV__49.wav` | 4.30s | 2616 | 18% |
| `WAV_RDV__55.wav` | 4.60s | 2602 | 11% |
| `WAV_RDV__64.wav` | 3.26s | 3629 | 31% |
| `WAV_RDV__65.wav` | 5.38s | 3250 | 15% |
| `WAV_RDV__69.wav` | 2.78s | 3590 | 20% |
| `WAV_RDV__70.wav` | 3.31s | 3000 | 23% |
| `WAV_RDV__71.wav` | 2.80s | 3691 | 17% |
| `WAV_RDV__79.wav` | 3.60s | 3451 | 14% |
| `WAV_RDV__88.wav` | 2.63s | 2453 | 21% |
| `WAV_RDV__93.wav` | 3.60s | 2818 | 20% |
| `WAV_RDV__94.wav` | 4.20s | 2482 | 16% |
| `WAV_RDV__95.wav` | 4.50s | 3418 | 27% |
| `WAV_RDV__96.wav` | 3.30s | 2981 | 37% |
| `WAV_RDV__97.wav` | 2.67s | 2270 | 19% |
| `WAV_RDV__99.wav` | 2.80s | 2203 | 8% |

## REVIEW_long

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__41.wav` | 6.11s | 3542 | 27% |
| `WAV_RDV__43.wav` | 12.42s | 3178 | 35% |
| `WAV_RDV__44.wav` | 12.15s | 763 | 15% |
| `WAV_RDV__66.wav` | 6.03s | 2918 | 14% |

## REVIEW_quiet

| file | dur | zcr | silence |
|---|---|---|---|
| `WAV_RDV__16.wav` | 1.42s | 701 | 98% |
| `WAV_RDV__23.wav` | 3.16s | 2995 | 81% |
| `WAV_RDV__39.wav` | 2.20s | 4709 | 97% |
| `WAV_RDV__4.wav` | 3.15s | 3509 | 85% |
| `WAV_RDV__53.wav` | 3.63s | 2731 | 99% |
| `WAV_RDV__75.wav` | 2.87s | 3192 | 97% |
| `WAV_RDV__77.wav` | 6.00s | 11770 | 96% |
| `WAV_RDV__85.wav` | 3.67s | 10243 | 91% |
| `WAV_RDV__91.wav` | 2.93s | 9869 | 80% |
