"""Loopback alias management for the camera mocks.

The app's camera IP field accepts a bare dotted quad only, and no port, so each
mock camera has to answer on its own address at port 80. On macOS the loopback
interface only carries 127.0.0.1 by default; the extra addresses have to be
added explicitly.

Aliases this module created are removed again on shutdown. Aliases that already
existed are left alone -- we only tear down what we set up.
"""

import platform
import subprocess

LOOPBACK_IF = "lo0"


class AliasManager:
    def __init__(self, log):
        self.log = log
        self._created = []

    @staticmethod
    def supported():
        return platform.system() == "Darwin"

    def _exists(self, ip):
        result = subprocess.run(
            ["ifconfig", LOOPBACK_IF],
            capture_output=True, text=True, check=False,
        )
        return f"inet {ip} " in result.stdout

    def ensure(self, ips):
        """Add any missing loopback aliases. Returns the list we created."""
        if not self.supported():
            self.log(
                "NET",
                f"Loopback aliasing is macOS-only; skipping on {platform.system()}",
            )
            return []

        for ip in ips:
            if ip == "127.0.0.1":
                continue
            if self._exists(ip):
                # Pre-existing: adopt it for this run but do not remove it on
                # exit, since we did not create it. Usually the residue of a
                # previous run that was killed hard rather than interrupted.
                self.log(
                    "NET",
                    f"Loopback alias {ip} already present; leaving it in place "
                    f"on exit (remove with: sudo ifconfig lo0 -alias {ip})",
                )
                continue
            result = subprocess.run(
                ["ifconfig", LOOPBACK_IF, "alias", ip, "255.255.255.255"],
                capture_output=True, text=True, check=False,
            )
            if result.returncode != 0:
                raise PermissionError(
                    f"could not add loopback alias {ip}: "
                    f"{result.stderr.strip() or 'permission denied'}"
                )
            self._created.append(ip)
            self.log("NET", f"Added loopback alias {ip}")
        return list(self._created)

    def teardown(self):
        for ip in self._created:
            subprocess.run(
                ["ifconfig", LOOPBACK_IF, "-alias", ip],
                capture_output=True, text=True, check=False,
            )
            self.log("NET", f"Removed loopback alias {ip}")
        self._created.clear()
