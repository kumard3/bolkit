# Brag Plan: Bolkit meetings (who said what)

## What is this app?
Bolkit for Mac records a call or an in-person conversation and turns it into a transcript split by speaker, with names, entirely on the Mac.

## The angle
The question every meeting recap fails: "who said that?" Bolkit answers it on-device. One mixed waveform splits into a lane per voice, the real app transcript shows the names it picked up, and the memory number proves it runs on a normal laptop.

## Hook (first 2-3 seconds)
One grey, mixed conversation waveform crawling across black, and "who said that?" huge.

## Key moments
- The waveform splits into four lanes (You, Rahul, Maya, Leo), each turn lighting up in the order it was spoken (real turn timings from the demo meeting).
- The real Bolkit transcript (rendered by the app itself from the pipeline's output) punches in on the names.
- An 18-minute call: 12.9 GB counts down to 5.6 GB peak.

## Outro / punchline
The Bolkit mark draws, "Bolkit", "free for Mac".

## User flow worth showing
Record a call → Bolkit separates the voices → named transcript.

## Tone
- Preset: polished (with cinematic restraint)
- Creative direction: quiet late-night product film, monochrome, one idea per beat
- Interpretation: few scenes, long readable holds, soft blur dissolves on bar lines

## Format: landscape, 1920x1080
## Duration: 22.0s (7.5 bars at 84 BPM, bar = 2.857s)

## Visual identity (from the project)
- Background #000, text #f5f5f7, greys #b6b6bd / #8e8e96 / #5c5c66, surface #141416, border #2a2a2e (Dashboard.swift Mono)
- Speaker colors as the app draws them: Rahul blue, Maya green, Leo orange, You white
- Display Bricolage Grotesque, body Hanken Grotesk, mono JetBrains Mono (same as the 2026-09-17 brag)
- Strongest visual: the real meeting transcript screen

## Verified claims (source)
- Mic = You, Mac audio = others, speakers separated automatically, up to 4 by NVIDIA Sortformer (MeetingPipeline.swift, FluidEngine.swift)
- In person: with nothing playing, the mic track is split into speakers (commit 058346d; needs the 1.3.2 release before posting)
- Names come only from what people say ("I'm Maya") (MeetingPipeline naming rule)
- 18-minute call: process 12.9 GB before the MLX cache cap, peak 5.6 GB after, on Kumar's 18 GB MacBook (measured 2026-09-17, memory bolkit-mac-mlx-only)
- On-device, no account, free (GitHub release)

## Share copy (draft)
Bolkit now tells you who said what in a meeting, on Zoom or around one table, and it all runs on your Mac.

## Audio direction
- Role: warm bed, sparse accents
- Music: original bolkit-pulse-84.wav, original 84 BPM minimal electronic bed from music/make_music.py (no third-party license)
- Treatment: fade in 0.3s, fade out over the last 1.2s
- Cue guidance: scene changes on bar lines (2.857, 8.571, 14.286, 18.571); lane turns on beats
- Audio-reactive: subtle, none beyond the music bed
- SFX: sparse. A soft click as each lane name lands, a drop as the transcript lands, one soft impact on the outro
- Restraint: no SFX on every segment

## Storyboard
### Scene 1, Hook, 0 to 2.857s
Mixed grey waveform crawls; "who said that?" slams in and holds 2s; small kicker "bolkit · meetings".
Transition: blur dissolve

### Scene 2, Split, 2.857 to 8.571s
The waveform splits into four labelled lanes; a playhead sweeps and each real turn lights in its speaker's lane. Caption "Bolkit splits every call by voice." then "on Zoom, or around one table." Each held at least 1.8s.
Sequential: 4 lane names on consecutive beats (0.714s apart)
Transition: blur dissolve

### Scene 3, Names, 8.571 to 14.286s
The real transcript screenshot rises in, slow push-in; highlight bars sweep under Rahul, Maya, Leo on beats. Caption "and it names people when they say it."
Transition: blur dissolve

### Scene 4, Memory, 14.286 to 18.571s
Kicker "an 18-minute call". Big counter 12.9 GB → 5.6 GB. Sub "peak memory, measured on an 18 GB MacBook". Then "nothing leaves your Mac."
Transition: blur dissolve

### Scene 5, Outro, 18.571 to 22.0s
Mark draws, "Bolkit", "free for Mac · github.com/kumard3/scribe".
