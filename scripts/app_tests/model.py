"""Shared data models used by the QEMU application test runner."""
from dataclasses import dataclass, field


@dataclass
class TestCase:
    """Describes one shell command and its expected console output."""

    name: str
    command: str
    contains: list[str] = field(default_factory=list)
    not_contains: list[str] = field(default_factory=list)
    regex: list[str] = field(default_factory=list)
    any_of: list[str] = field(default_factory=list)
    timeout: float = 8.0
    recover_timeout: float | None = None
    delay_before: float = 0.0
    number: int = 0


@dataclass
class TestSection:
    """Groups test cases displayed and executed under one heading."""

    name: str
    tests: list[TestCase]
