#!/usr/bin/env python3
"""
Simple ElevenLabs speech-to-text helper.

Usage:
    python stt_demo.py --file /absolute/path/to/audio.wav
    python stt_demo.py --file /absolute/path/to/audio.mp3 --save-text /tmp/transcript.txt
"""

import argparse
import json
import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Transcribe an audio file using ElevenLabs speech-to-text.")
    parser.add_argument(
        "--file",
        type=Path,
        required=True,
        help="Absolute path to an audio file (wav/mp3/flac/etc).",
    )
    parser.add_argument(
        "--model-id",
        type=str,
        default="scribe_v1",
        help="ElevenLabs STT model identifier (default: scribe_v1).",
    )
    parser.add_argument(
        "--save-text",
        type=Path,
        default=None,
        help="Optional absolute path to save the transcript as plain text.",
    )
    parser.add_argument(
        "--save-json",
        type=Path,
        default=None,
        help="Optional absolute path to save the full JSON response.",
    )

    args = parser.parse_args()

    if not args.file.is_absolute():
        parser.error("--file path must be absolute.")
    if args.save_text and not args.save_text.is_absolute():
        parser.error("--save-text path must be absolute.")
    if args.save_json and not args.save_json.is_absolute():
        parser.error("--save-json path must be absolute.")

    if not args.file.exists():
        parser.error(f"Audio file {args.file} does not exist.")

    return args


def extract_transcript(response: Any) -> str:
    if isinstance(response, dict):
        for key in ("text", "transcript", "transcription"):
            value = response.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        raise ValueError(f"Could not find transcript in response keys: {list(response.keys())}")

    text_attr = getattr(response, "text", None)
    if isinstance(text_attr, str) and text_attr.strip():
        return text_attr.strip()

    transcript_attr = getattr(response, "transcript", None)
    if isinstance(transcript_attr, str) and transcript_attr.strip():
        return transcript_attr.strip()

    transcription_attr = getattr(response, "transcription", None)
    if isinstance(transcription_attr, str) and transcription_attr.strip():
        return transcription_attr.strip()

    raise ValueError("Unable to extract transcript from ElevenLabs response.")


def main() -> int:
    load_dotenv()
    args = parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY is not set. Add it to your environment or .env file.")

    try:
        from elevenlabs import ElevenLabs
    except ImportError as exc:
        raise SystemExit("elevenlabs package not installed. Run `pip install elevenlabs`.") from exc

    with args.file.open("rb") as audio_file:
        audio_bytes = audio_file.read()

    client = ElevenLabs(api_key=api_key)

    try:
        response = client.speech_to_text.convert(
            file=audio_bytes,
            model_id=args.model_id,
        )
    except Exception as exc:  # pylint: disable=broad-except
        raise SystemExit(f"Speech-to-text request failed: {exc}") from exc

    if args.save_json:
        args.save_json.parent.mkdir(parents=True, exist_ok=True)
        if hasattr(response, "model_dump_json"):
            args.save_json.write_text(response.model_dump_json(indent=2), encoding="utf-8")
        else:
            args.save_json.write_text(json.dumps(response, indent=2, default=str), encoding="utf-8")

    if hasattr(response, "model_dump"):
        transcript = extract_transcript(response.model_dump())
    else:
        transcript = extract_transcript(response)

    print("Transcription:")
    print(transcript)

    if args.save_text:
        args.save_text.parent.mkdir(parents=True, exist_ok=True)
        args.save_text.write_text(transcript + "\n", encoding="utf-8")
        print(f"\nSaved transcript to {args.save_text}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


