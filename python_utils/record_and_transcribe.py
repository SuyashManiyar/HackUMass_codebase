#!/usr/bin/env python3
"""
Record live audio from the default macOS microphone and transcribe it with ElevenLabs STT.

Requirements:
    - ffmpeg (installed via Homebrew in this project)
    - elevenlabs Python SDK

Example:
    python record_and_transcribe.py \
        --duration 8 \
        --save-audio /Users/me/Documents/live.wav \
        --save-text /Users/me/Documents/live_transcript.txt
"""

import argparse
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

from dotenv import load_dotenv


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record microphone audio and transcribe it with ElevenLabs.")
    parser.add_argument(
        "--duration",
        type=float,
        default=8.0,
        help="Recording length in seconds (default: 8).",
    )
    parser.add_argument(
        "--save-audio",
        type=Path,
        default=None,
        help="Optional absolute path to save the captured audio file (WAV).",
    )
    parser.add_argument(
        "--save-text",
        type=Path,
        default=None,
        help="Optional absolute path to save the transcript (plain text).",
    )
    parser.add_argument(
        "--save-json",
        type=Path,
        default=None,
        help="Optional absolute path to save the raw JSON response from ElevenLabs.",
    )
    parser.add_argument(
        "--model-id",
        type=str,
        default="scribe_v1",
        help="ElevenLabs STT model identifier (default: scribe_v1).",
    )

    args = parser.parse_args()

    if args.duration <= 0:
        parser.error("--duration must be positive.")
    if args.save_audio and not args.save_audio.is_absolute():
        parser.error("--save-audio must be an absolute path.")
    if args.save_text and not args.save_text.is_absolute():
        parser.error("--save-text must be an absolute path.")
    if args.save_json and not args.save_json.is_absolute():
        parser.error("--save-json must be an absolute path.")

    return args


def ensure_ffmpeg() -> None:
    try:
        subprocess.run(["ffmpeg", "-version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise SystemExit(
            "ffmpeg is required for live recording. Install via Homebrew: `brew install ffmpeg`."
        ) from exc


def record_audio(duration: float, destination: Path) -> None:
    print("Mic capture started (ffmpeg). Speak when ready...")
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "avfoundation",
        "-i",
        ":0",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-t",
        str(duration),
        str(destination),
    ]
    print(f"Recording {duration:.1f} seconds of audio... (press Ctrl+C to stop early)")
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"ffmpeg failed to capture audio: {exc}") from exc
    print(f"Mic capture stopped. Saved raw audio to {destination}")


def extract_transcript(response: Any) -> str:
    if isinstance(response, dict):
        for key in ("text", "transcript", "transcription"):
            value = response.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        raise ValueError(f"Could not find transcript in response keys: {list(response.keys())}")

    for attr in ("text", "transcript", "transcription"):
        value = getattr(response, attr, None)
        if isinstance(value, str) and value.strip():
            return value.strip()

    raise ValueError("Unable to extract transcript from ElevenLabs response.")


def main() -> int:
    load_dotenv()
    args = parse_args()
    ensure_ffmpeg()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        raise SystemExit("ELEVENLABS_API_KEY is not set. Add it to your environment or .env file.")

    try:
        from elevenlabs import ElevenLabs
    except ImportError as exc:
        raise SystemExit("elevenlabs package not installed. Run `pip install elevenlabs`.") from exc

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    if args.save_audio:
        audio_path = args.save_audio
        if audio_path.exists():
            audio_path = audio_path.with_name(f"{audio_path.stem}_{timestamp}{audio_path.suffix or '.wav'}")
            print(f"Existing audio file detected. Saving new recording to {audio_path}")
        audio_path.parent.mkdir(parents=True, exist_ok=True)
    else:
        tmp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        audio_path = Path(tmp_file.name)
        tmp_file.close()

    try:
        record_audio(args.duration, audio_path)
    except KeyboardInterrupt:
        print("\n🔹 Recording interrupted — attempting transcription anyway…")

    client = ElevenLabs(api_key=api_key)

    if not audio_path.exists():
        if not args.save_audio:
            audio_path.unlink(missing_ok=True)
        raise SystemExit("No audio file was captured, aborting transcription.")

    with audio_path.open("rb") as audio_file:
        audio_bytes = audio_file.read()

    try:
        response = client.speech_to_text.convert(
            file=audio_bytes,
            model_id=args.model_id,
        )
    except Exception as exc:  # pylint: disable=broad-except
        if not args.save_audio:
            audio_path.unlink(missing_ok=True)
        raise SystemExit(f"Speech-to-text request failed: {exc}") from exc

    transcript = extract_transcript(response.model_dump() if hasattr(response, "model_dump") else response)

    print("\nTranscript:")
    print(transcript)

    if args.save_text:
        text_path = args.save_text
        if text_path.exists():
            text_path = text_path.with_name(f"{text_path.stem}_{timestamp}{text_path.suffix or '.txt'}")
            print(f"Existing transcript file detected. Saving new transcript to {text_path}")
        text_path.parent.mkdir(parents=True, exist_ok=True)
        text_path.write_text(transcript + "\n", encoding="utf-8")
        print(f"\nSaved transcript to {text_path}")

    if args.save_json:
        json_path = args.save_json
        if json_path.exists():
            json_path = json_path.with_name(f"{json_path.stem}_{timestamp}{json_path.suffix or '.json'}")
            print(f"Existing JSON file detected. Saving new response to {json_path}")
        json_path.parent.mkdir(parents=True, exist_ok=True)
        if hasattr(response, "model_dump_json"):
            json_path.write_text(response.model_dump_json(indent=2), encoding="utf-8")
        else:
            json_path.write_text(str(response), encoding="utf-8")
        print(f"Saved raw JSON response to {json_path}")

    if not args.save_audio:
        audio_path.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


