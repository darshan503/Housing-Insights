"""Shared fixtures. APP_BASE_URL is the environment root, e.g. https://<env>.outsystemscloud.com;
the UI module is served at {APP_BASE_URL}/SingaporeHousingInsights. Tests that need the deployed
app are skipped when APP_BASE_URL is not set."""
import os

import pytest

UI_MODULE = "SingaporeHousingInsights"


@pytest.fixture(scope="session")
def ui_url() -> str:
    url = os.environ.get("APP_BASE_URL", "").rstrip("/")
    if not url:
        pytest.skip("APP_BASE_URL not set; skipping tests against the deployed app")
    return f"{url}/{UI_MODULE}"
