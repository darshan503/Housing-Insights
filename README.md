# Singapore Housing Insights

An OutSystems Reactive app for exploring HDB resale flat prices, read **live** from the
public data.gov.sg dataset *Resale flat prices based on registration date from Jan-2017
onwards* (`d_8b84c4ee58e3cfc0ece0d773c8ca6abc`). The repository also holds the AWS
infrastructure-as-code for a self-managed OutSystems platform and the automated tests.

**Live app:** https://personal-mptcomx3.outsystemscloud.com/SingaporeHousingInsights/
(choose **Login as Demo User** on the sign-in page).

| Screen | What it does |
|---|---|
| Dashboard | KPIs (transactions, average price, highest price, average price per m²) and four charts — monthly price trend, average price by town, sales by flat type, average price by storey range — for the last 6 months, filterable by town, flat type and month range |
| Transactions | Paged, searchable list of every resale transaction (240,000+), filterable by town, flat type, flat model and month range, newest first |

## Architecture

```
SingaporeHousingInsights   (End-user)  screens, theme, demo sign-in
        │ uses
HousingInsights_CS         (Core)      dashboard maths, search orchestration, ResaleTransaction structure
        │ uses
HousingInsights_IS         (Integration) ResaleSearch → data.gov.sg datastore_search
        │ HTTPS
data.gov.sg
```

**No local copy of the data.** There are no entities and no sync timer; every screen reads
data.gov.sg at request time.

* `HousingInsights_IS.ResaleSearch` is the only module that talks to data.gov.sg. It builds
  the exact-match `filters` JSON (town, flat type, flat model, a list of months), allow-lists
  the sort field, strips punctuation from the free-text query (upstream answers HTTP 409
  otherwise), clamps `Limit` to 1–5,000, and never throws: it returns `IsSuccess` and a safe
  `ErrorMessage`. An optional `x-api-key` header comes from the secret site property
  `DataGovSG_ApiKey`, which raises the anonymous rate limit.
* `HousingInsights_CS.FetchRows` pulls the dashboard window one month per call (a nationwide
  month is ~2,000 rows, under the 5,000 cap) with only the 8 columns the charts need, and is
  cached for 10 minutes so filter changes don't re-hit upstream. `Aggregate` groups and averages
  in memory for each chart.
* `HousingInsights_CS.SearchTransactions` maps the screen's filters and paging straight onto one
  upstream call, so the Transactions list pages through the full dataset server-side.
* Screens show a red banner with the safe message when upstream is unavailable or rate-limited.

## Changes from the first version

The first version copied the dataset into a `ResaleTransaction` entity with a timer and a
manual "Fetch data" button. It was reworked to read live:

| Area | Before | After |
|---|---|---|
| Module names | `HousingInsights_integration`, `HousingInsights_core` | `HousingInsights_IS`, `HousingInsights_CS` (OutSystems layer suffixes) |
| Data | Entity + sync timer + Fetch button | Live calls; entity, timer, sync actions and button removed |
| REST | `Data.GetData`, snake_case attributes, unused theme references | `DataGovSG.DatastoreSearch`, PascalCase structures, `ResaleSearch` wrapper with validation |
| Bug | `lease_commence_date` mapped as Date; upstream sends a bare year (`1976`), so every call failed to deserialise | Mapped as Text, converted to `LeaseCommenceYear` Integer |
| Bug | Free-text search with punctuation (`AVE-10`) returned HTTP 409 | Query sanitised in the IS |
| Errors | No user-facing message when the upstream call failed | Safe message returned and shown in a banner |
| Filters | Price min/max filtered client-side on a partial page | Removed; all remaining filters are applied upstream so totals and paging are exact |
| Charts | Unordered towns and storey ranges | Sorted (towns A–Z or by value, storeys in order) |

## Tests

| Suite | Where | Needs | Count |
|---|---|---|---|
| Upstream contract | `tests/contract` | internet | 15 |
| End-to-end (Playwright) | `tests/e2e` | `APP_BASE_URL` | 6 |
| IaC unit (mocked AWS) | `outsystems-aws-iac/tests` | Terraform ≥ 1.7 | 35 runs / 70 assertions |
| IaC environment policy | `outsystems-aws-iac/tests/policy` × 4 envs | Terraform ≥ 1.7 | 6 per env |
| IaC static analysis | fmt, validate, tflint, checkov | — | checkov 195 passed |
| IaC integration | `outsystems-aws-iac/tests/integration` | AWS account (manual) | — |

```bash
pip install -r tests/requirements.txt && python -m playwright install chromium
pytest tests/contract -m contract
APP_BASE_URL=https://personal-mptcomx3.outsystemscloud.com pytest tests/e2e -m e2e --browser chromium

cd outsystems-aws-iac
terraform init -backend=false && terraform test
terraform test -test-directory=tests/policy -var-file=environments/prod.tfvars
```

The contract tests pin every upstream assumption the modules rely on: field names, the
`YYYY-MM` month and bare-year lease formats, exact-match and month-list filters, server-side
sort on each allowed field, the 5,000-row month window, and the 409 on punctuation. Set
`DATAGOV_API_KEY` to avoid anonymous rate limiting.

CI (`.github/workflows/ci.yml`) runs static analysis, unit and policy tests and the contract
tests on every push and pull request; nightly it also runs the E2E suite against the
environment in the `APP_BASE_URL` repository variable. The real-AWS integration test is
manual (`workflow_dispatch`).

## Infrastructure

See [`outsystems-aws-iac/README.md`](outsystems-aws-iac/README.md): VPC across two AZs, ALB
with WAF (managed rules, rate limit, request logging), front-end Auto Scaling group,
Deployment Controller, RDS SQL Server, KMS-encrypted storage and logs, CloudWatch alarms,
and per-environment sizing for dev, test, prod and LifeTime.

## Possible next steps

* A `HousingInsights_Tests` module for unit tests of `ResaleSearch` input rules and `Aggregate`.
* Export of the filtered Transactions list.
* A longer dashboard window, which would need a scheduled snapshot because upstream has no
  aggregation endpoint.
