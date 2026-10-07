"""Load config/omeka-test/settings.yaml (SSOT for the test stack)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None  # type: ignore

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SETTINGS = REPO_ROOT / "config" / "omeka-test" / "settings.yaml"
SETTINGS_LOCAL = REPO_ROOT / "config" / "omeka-test" / "settings.local.yaml"
LEGACY_API = REPO_ROOT / "config" / "omeka-test" / "omeka-api.yaml"


def deep_merge(base: dict, overlay: dict) -> dict:
    out = dict(base)
    for key, val in overlay.items():
        if isinstance(val, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], val)
        else:
            out[key] = val
    return out


def load_settings(path: Path | None = None) -> dict:
    if yaml is None:
        print("PyYAML required", file=sys.stderr)
        raise SystemExit(1)
    settings_path = path or Path(os.environ.get("OMEKA_TEST_SETTINGS", DEFAULT_SETTINGS))
    if not settings_path.is_file():
        raise FileNotFoundError(
            f"Missing {settings_path} — run ./scripts/ensure-local-config.sh"
        )
    data = yaml.safe_load(settings_path.read_text(encoding="utf-8")) or {}
    local_path = settings_path.parent / "settings.local.yaml"
    if local_path.is_file():
        local = yaml.safe_load(local_path.read_text(encoding="utf-8")) or {}
        data = deep_merge(data, local)
    return data


def resolve_api_config(settings: dict | None = None) -> dict:
    """REST API settings for local Python tools (align with hitsave-archiver omeka-uploader.yaml)."""
    settings = settings if settings is not None else load_settings()
    omeka = settings.get("omeka") or {}
    api = dict(settings.get("api") or {})
    if not api and LEGACY_API.is_file() and yaml is not None:
        api = dict(yaml.safe_load(LEGACY_API.read_text(encoding="utf-8")).get("api") or {})
    api.setdefault("site_slug", omeka.get("site_slug", "hitsave-test"))
    api.setdefault("item_set_title", omeka.get("item_set_title", "Press and Marketing Materials"))
    api.setdefault("default_is_public", False)
    api.setdefault("dip_ingester", "omeka_dip_package")
    api.setdefault("production_item_set_id", 1459)
    if not api.get("base_url"):
        public = str(omeka.get("public_url", "http://127.0.0.1:8088")).rstrip("/")
        api["base_url"] = f"{public}/api"
    if not api.get("credentials_file"):
        api["credentials_file"] = "secrets/omeka-api-credentials-local.yaml"
    return api
