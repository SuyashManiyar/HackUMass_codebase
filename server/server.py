import socket

import uvicorn

from server.main import app


def _log_server_addresses() -> None:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
    except Exception:  # noqa: BLE001 - best effort
        local_ip = "127.0.0.1"
    finally:
        s.close()

    print("\n" + "=" * 60)
    print("🚀 HackUMass OCR Slide Server")
    print("=" * 60)
    print("📍 Server running on:")
    print("   Local:   http://127.0.0.1:8000")
    print(f"   Network: http://{local_ip}:8000")
    print(f"\n📡 API Endpoint: http://{local_ip}:8000/process_slide")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    _log_server_addresses()
    uvicorn.run(app, host="0.0.0.0", port=8000)
