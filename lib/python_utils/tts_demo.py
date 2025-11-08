#!/usr/bin/env python3
"""
Simple ElevenLabs text-to-speech helper.

Usage:
    python tts_demo.py --text "Hello from ElevenLabs!"
    python tts_demo.py --file /home/pi/summary.json --voice-id "Rachel"
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from dotenv import load_dotenv
def resolve_voice_id(client, voice_identifier: str) -> str:
    candidate = voice_identifier.strip()
    if candidate and " " not in candidate and len(candidate) >= 12:
        return candidate

    try:
        voices_response = client.voices.get_all()
    except Exception as exc:
        raise SystemExit(
            "Voice names require the voices_read permission. "
            "Provide a voice_id (e.g. 21m00Tcm4TlvDq8ikWAM for Rachel) or use an API key with voices_read."
        ) from exc
    voices = getattr(voices_response, "voices", []) or []

    for voice in voices:
        if getattr(voice, "voice_id", "") == voice_identifier:
            return voice_identifier

    for voice in voices:
        name = getattr(voice, "name", "")
        if isinstance(name, str) and name.lower() == voice_identifier.lower():
            return getattr(voice, "voice_id")

    available = ", ".join(f"{getattr(v, 'name', '?')} ({getattr(v, 'voice_id', 'unknown')})" for v in voices)
    raise SystemExit(
        f"Voice '{voice_identifier}' not found. Available voices:\n{available or 'none'}"
    )


def build_text_from_json(data: dict) -> str:
    sections: list[str] = []

    summary = data.get("summary") or data.get("text")
    if isinstance(summary, str) and summary.strip():
        sections.append(summary.strip())

    bullets = data.get("bullet_points") or data.get("bullets")
    if isinstance(bullets, list):
        clean = [str(item).strip() for item in bullets if str(item).strip()]
        if clean:
            bullet_sentence = "Key points are: " + " ".join(
                f"{idx + 1}) {point}." for idx, point in enumerate(clean)
            )
            sections.append(bullet_sentence)

    visual = data.get("visual_description") or data.get("visuals")
    if isinstance(visual, str) and visual.strip():
        sections.append(f"Visually: {visual.strip()}")

    if not sections:
        raise ValueError("JSON file does not contain expected summary fields.")

    return " ".join(sections).strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert text or JSON summary to speech using ElevenLabs.")
    text_group = parser.add_mutually_exclusive_group(required=True)
    text_group.add_argument(
        "--text",
        type=str,
        help="Plain text to speak.",
    )
    text_group.add_argument(
        "--file",
        type=Path,
        help="Path to a JSON file with fields like summary/bullet_points for speech synthesis.",
    )
    parser.add_argument(
        "--voice-id",
        type=str,
        default="21m00Tcm4TlvDq8ikWAM",
        help="ElevenLabs voice identifier or display name (default: Rachel).",
    )
    parser.add_argument(
        "--model-id",
        type=str,
        default="eleven_multilingual_v2",
        help="ElevenLabs model identifier (default: eleven_multilingual_v2).",
    )
    parser.add_argument(
        "--save-path",
        type=Path,
        default=None,
        help="Optional absolute path to save the generated audio (WAV).",
    )
    parser.add_argument(
        "--no-playback",
        action="store_true",
        help="Skip playback and only save the audio file.",
    )

    args = parser.parse_args()

    if args.file and not args.file.is_absolute():
        parser.error("--file path must be absolute.")
    if args.save_path and not args.save_path.is_absolute():
        parser.error("--save-path must be absolute.")

    return args


def load_text(args: argparse.Namespace) -> str:
    if args.text:
        return args.text.strip()

    if not args.file.exists():
        example = {
            "summary": "This is a sample summary generated automatically for testing.",
            "bullet_points": [
                "Bullet point one demonstrates how key ideas are listed.",
                "Bullet point two helps verify that numbered speech works.",
            ],
            "visual_description": "Imagine a simple slide showing a title and two bullet points.",
        }
        args.file.parent.mkdir(parents=True, exist_ok=True)
        with args.file.open("w", encoding="utf-8") as fh:
            json.dump(example, fh, indent=2)
        print(f"No JSON found at {args.file}. Created a demo file with example content.")

    with args.file.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    return build_text_from_json(data)


def main() -> int:
    load_dotenv()
    args = parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY is not set. Add it to env.example/.env or export it before running.")

    text = load_text(args)
    if not text:
        raise SystemExit("No text to speak after processing.")

    try:
        from elevenlabs import ElevenLabs
        from elevenlabs.play import play
    except ImportError as exc:
        raise SystemExit("elevenlabs package not installed. Run `pip install elevenlabs`.") from exc

    client = ElevenLabs(api_key=api_key)
    resolved_voice_id = resolve_voice_id(client, args.voice_id)
    audio_stream = client.text_to_speech.convert(
        voice_id=resolved_voice_id,
        model_id=args.model_id,
        text=text,
    )

    if isinstance(audio_stream, (bytes, bytearray)):
        audio_chunks = [bytes(audio_stream)]
    else:
        audio_chunks = list(audio_stream)
    audio_bytes = b"".join(audio_chunks)

    if args.save_path:
        args.save_path.parent.mkdir(parents=True, exist_ok=True)
        with args.save_path.open("wb") as file_handle:
            file_handle.write(audio_bytes)

    if args.no_playback:
        if args.save_path:
            print(f"Audio saved to {args.save_path}")
        else:
            print("Playback disabled. You did not specify --save-path; audio was not saved.")
        return 0

    try:
        play((chunk for chunk in audio_chunks))
    except ValueError as exc:
        message = str(exc).lower()
        if "ffplay" not in message:
            raise
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_file:
            tmp_file.write(audio_bytes)
            temp_path = Path(tmp_file.name)
        print(
            "ffplay (from ffmpeg) is not installed. Falling back to system player.",
            file=sys.stderr,
        )
        player = "afplay" if sys.platform == "darwin" else "aplay"
        try:
            subprocess.run([player, str(temp_path)], check=True)
        finally:
            temp_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


