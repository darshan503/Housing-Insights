"""Upstream contract tests for the HDB resale dataset on data.gov.sg.

The app reads data.gov.sg live (no local copy), so these pin every assumption that
HousingInsights_IS.ResaleSearch and HousingInsights_CS make. They need only internet
access (marker: contract) and run on every push and nightly.
"""
import os
import re
import time

import pytest
import requests

pytestmark = pytest.mark.contract

RESOURCE_ID = os.environ.get("DATAGOV_RESOURCE_ID", "d_8b84c4ee58e3cfc0ece0d773c8ca6abc")
URL = "https://data.gov.sg/api/action/datastore_search"
HEADERS = {"x-api-key": os.environ["DATAGOV_API_KEY"]} if os.environ.get("DATAGOV_API_KEY") else {}

# Fields mapped by the ResaleRecord REST structure (NameInJSON).
EXPECTED_FIELDS = {
    "_id", "month", "town", "flat_type", "block", "street_name", "storey_range",
    "floor_area_sqm", "flat_model", "lease_commence_date", "remaining_lease", "resale_price",
}
# Must match the SortBy allow-list in ResaleSearch.
SORTABLE = ["month", "town", "flat_type", "storey_range", "resale_price"]
DASHBOARD_FIELDS = "_id,month,town,flat_type,flat_model,storey_range,floor_area_sqm,resale_price"


def get(**params):
    """Paced GET with backoff: anonymous data.gov.sg traffic is rate-limited (HTTP 429)."""
    for attempt in range(6):
        time.sleep(0 if HEADERS else 2.5)
        r = requests.get(URL, params={"resource_id": RESOURCE_ID, **params}, headers=HEADERS, timeout=60)
        if r.status_code != 429:
            return r
        time.sleep(10 * (attempt + 1))
    pytest.fail("data.gov.sg kept returning HTTP 429; set DATAGOV_API_KEY")


def fetch(**params):
    r = get(**params)
    r.raise_for_status()
    body = r.json()
    assert body["success"] is True, body
    return body["result"]


@pytest.fixture(scope="module")
def sample():
    return fetch(limit=500, sort="month desc")


def test_fields_unchanged(sample):
    assert EXPECTED_FIELDS <= {f["id"] for f in sample["fields"]}


def test_dataset_size_plausible(sample):
    assert sample["total"] > 200_000


def test_value_formats_the_mapping_relies_on(sample):
    for rec in sample["records"]:
        assert re.match(r"^\d{4}-(0[1-9]|1[0-2])$", rec["month"]), rec          # ToTransaction: month + "-01"
        assert re.match(r"^\d{4}$", str(rec["lease_commence_date"])), rec     # bare year -> REST attr is Text, not Date
        assert float(rec["floor_area_sqm"]) > 0, rec                          # text upstream, parsed with TextToDecimal
        assert float(rec["resale_price"]) > 0, rec
        assert re.match(r"^\d{2} TO \d{2}$", rec["storey_range"]), rec


def test_month_list_filter_equals_sum_of_months():
    # FetchRows asks one month at a time; SearchTransactions sends a month list. Both must agree.
    one = fetch(limit=1, filters='{"month":"2024-01"}')["total"]
    two = fetch(limit=1, filters='{"month":"2024-02"}')["total"]
    both = fetch(limit=1, filters='{"month":["2024-01","2024-02"]}')["total"]
    assert one > 0 and two > 0 and both == one + two


def test_exact_town_and_flat_type_filters():
    res = fetch(limit=50, filters='{"town":"BISHAN","flat_type":"4 ROOM"}')
    assert res["total"] > 0
    assert all(r["town"] == "BISHAN" and r["flat_type"] == "4 ROOM" for r in res["records"])


def test_one_month_fits_in_one_dashboard_call():
    # FetchRows requests Limit 5000 per month; a nationwide month must not exceed that.
    res = fetch(limit=5000, filters='{"month":"2024-06"}', fields=DASHBOARD_FIELDS)
    assert 0 < res["total"] <= 5000 and len(res["records"]) == res["total"]
    assert set(res["records"][0]) == set(DASHBOARD_FIELDS.split(","))


@pytest.mark.parametrize("field", SORTABLE)
def test_server_side_sort_on_every_allowed_field(field):
    key = (lambda v: float(v)) if field == "resale_price" else (lambda v: re.sub(r"[^0-9a-z]", "", str(v).lower()))
    desc = [key(r[field]) for r in fetch(limit=30, sort=f"{field} desc", fields=field)["records"]]
    assert all(a >= b for a, b in zip(desc, desc[1:])), desc


def test_floor_area_is_text_so_it_is_not_sortable_server_side(sample):
    types = {f["id"]: f["type"] for f in sample["fields"]}
    assert types["floor_area_sqm"] == "text" and types["resale_price"] == "numeric"


def test_empty_optional_parameters_are_accepted():
    assert fetch(limit=2, sort="", q="", filters="", fields="")["records"]


@pytest.mark.parametrize("raw,clean", [("AVE-10", "AVE 10"), ("ANG MO KIO.", "ANG MO KIO")])
def test_punctuation_in_q_is_rejected_so_the_is_strips_it(raw, clean):
    assert get(q=raw, limit=1).status_code == 409
    fetch(q=clean, limit=1)
