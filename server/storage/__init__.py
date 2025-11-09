"""Storage helpers for persisting slide state and history."""

from .manager import (
    SlideState,
    append_slide_history,
    load_last_state,
    load_slide_history,
    reset_slide_history,
    save_last_state,
)

__all__ = [
    "SlideState",
    "append_slide_history",
    "load_last_state",
    "load_slide_history",
    "reset_slide_history",
    "save_last_state",
]


