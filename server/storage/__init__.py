"""Storage helpers for persisting slide state."""

from .manager import SlideState, load_last_state, save_last_state

__all__ = ["SlideState", "load_last_state", "save_last_state"]


