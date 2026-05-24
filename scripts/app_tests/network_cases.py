"""Optional external network connectivity smoke test cases."""
from .model import TestCase


def network_tests(host_ip: str, delay: float) -> list[TestCase]:
    """Returns network smoke tests executed only when networking is enabled."""
    return [
        TestCase(
            "ping gateway",
            f"ping {host_ip}",
            [f"PING {host_ip}"],
            any_of=["reply from", "timeout from"],
            timeout=12.0,
            delay_before=delay,
        ),
        TestCase(
            "nslookup example.com",
            "nslookup example.com",
            ["Name: example.com"],
            any_of=["Address:", "nslookup: no A record"],
            timeout=30.0,
            delay_before=delay,
        ),
        TestCase(
            "curl example.com http",
            "curl -i http://example.com",
            ["HTTP/1.1 200 OK"],
            timeout=30.0,
            recover_timeout=120.0,
            delay_before=delay,
        ),
        TestCase(
            "curl example.com https",
            "curl -v https://example.com",
            ["TLS: TLS1.3"],
            timeout=45.0,
            recover_timeout=180.0,
            delay_before=delay,
        ),
    ]
