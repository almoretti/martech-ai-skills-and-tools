"""gmc-cli — Google Merchant Center CLI (Merchant API v1)."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("gmc-cli")
except PackageNotFoundError:  # running from a source checkout
    __version__ = "0.0.0.dev0"
