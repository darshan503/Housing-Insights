"""End-to-end tests of the live Singapore Housing Insights app (Playwright).
Run with: pytest tests/e2e -m e2e --browser chromium   (APP_BASE_URL required)

Screens read data.gov.sg live, so assertions check behaviour (counts, filtering, ordering,
no error banner) rather than exact values."""
import re

import pytest
from playwright.sync_api import Page, expect

pytestmark = pytest.mark.e2e
LOAD = 90_000  # first dashboard load fetches 6 months live (cached afterwards)


def number(text: str) -> int:
    return int(re.sub(r"[^\d]", "", text))


@pytest.fixture
def signed_in(page: Page, ui_url):
    page.goto(f"{ui_url}/Login")
    page.get_by_role("button", name="Login as Demo User").click()
    expect(page.locator(".highcharts-container").first).to_be_visible(timeout=LOAD)
    return page


def showing_total(page: Page) -> int:
    line = page.get_by_text(re.compile(r"Showing \d"))
    expect(line).to_be_visible(timeout=LOAD)
    return number(line.inner_text().split(" of ")[1])


def test_dashboard_shows_live_kpis_and_four_charts(signed_in: Page):
    expect(signed_in.locator(".highcharts-container")).to_have_count(4, timeout=LOAD)
    body = signed_in.inner_text("body")
    tx = re.search(r"Transactions\s*\n\s*([\d,]+)", body)
    assert tx and number(tx.group(1)) > 1_000, "6-month window should hold thousands of sales"
    expect(signed_in.locator(".data-error")).to_have_count(0)


def test_filter_options_are_sorted(signed_in: Page):
    towns = signed_in.eval_on_selector("#Dropdown1", "s => [...s.options].slice(1).map(o => o.text)")
    assert len(towns) > 20 and towns == sorted(towns)


def test_storey_chart_is_in_storey_order(signed_in: Page):
    labels = signed_in.eval_on_selector_all(
        ".highcharts-container", "cs => [...cs[cs.length - 1].querySelectorAll('.highcharts-xaxis-labels text')].map(t => t.textContent)")
    assert labels and labels == sorted(labels)


def test_town_filter_changes_dashboard(signed_in: Page):
    before = signed_in.inner_text("body")
    signed_in.select_option("#Dropdown1", label="BISHAN")
    expect(signed_in.locator("body")).not_to_have_text(before, timeout=LOAD)
    expect(signed_in.locator(".data-error")).to_have_count(0)


def test_transactions_list_is_live_and_complete(signed_in: Page, ui_url):
    signed_in.goto(f"{ui_url}/Transactions")
    assert showing_total(signed_in) > 200_000
    expect(signed_in.locator("table tbody tr")).to_have_count(25)
    expect(signed_in.locator(".data-error")).to_have_count(0)
    # sync-era controls are gone
    expect(signed_in.get_by_role("button", name=re.compile("fetch", re.I))).to_have_count(0)
    expect(signed_in.get_by_text(re.compile(r"price \(S\$\)"))).to_have_count(0)


def test_transactions_town_filter(signed_in: Page, ui_url):
    signed_in.goto(f"{ui_url}/Transactions")
    everything = showing_total(signed_in)
    signed_in.select_option("#Dropdown1", label="BISHAN")
    expect(signed_in.get_by_text(re.compile(r"Showing \d"))).not_to_have_text(re.compile(f"of {everything:,} "), timeout=LOAD)
    assert 0 < showing_total(signed_in) < everything
    towns = signed_in.eval_on_selector_all("table tbody tr", "rs => rs.map(r => r.cells[1].innerText.trim())")
    assert towns and set(towns) == {"BISHAN"}
