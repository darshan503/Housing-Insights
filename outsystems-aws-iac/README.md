# Singapore Housing Insights: OutSystems Platform on AWS (Infrastructure as Code)

This repository has the Terraform **Infrastructure as Code** that defines the AWS infrastructure needed to
**deploy and operate a self-managed OutSystems 11 platform**. It also has a layered **automated test suite**.

It hosts the three OutSystems modules of the *Singapore Housing Insights* application:

| Module | Layer (Architecture Canvas) | Purpose | Infrastructure impact |
|---|---|---|---|
| `SingaporeHousingInsights` | End-user | Reactive UI and user interaction | Exposed via the ALB at `/SingaporeHousingInsights/`; used as the ALB health check |
| `HousingInsights_core` | Core | Data model (`ResaleTransaction`) and business logic | Entities live in the Platform catalog on **RDS SQL Server** |
| `HousingInsights_integration` | Integration | REST calls to `https://data.gov.sg` (HDB resale data) | Front-ends need **outbound HTTPS through the NAT gateway** |

All three modules are published to the same OutSystems environment, so they share one server farm. Each
environment (Dev, Test, Prod, and a dedicated LifeTime environment) is a separate, isolated copy of this stack.

---

## 1. Architecture

```
                         Internet
                            │
                     ┌──────▼──────┐   AWS WAF (managed rules + rate limit)
                     │     ALB     │   HTTP→HTTPS 301 · TLS 1.2/1.3 · /ServiceCenter & /LifeTime → 403
  Public subnets     └──────┬──────┘   (except management CIDRs, e.g. LifeTime NAT IPs)
  ──────────────────────────┼──────────────────────────────────────────────── NAT GW (1 or 1 per AZ)
                            │ HTTPS 443 (re-encrypted)
  Private app       ┌───────▼────────┐  12000 / 5672   ┌──────────────────────────┐
  subnets           │ Front-end ASG  │────────────────►│  Deployment Controller   │
                    │ Windows 2022   │◄────────────────│  (+ Service Center)      │
                    │ IIS + Platform │      12001      │  Windows 2022            │
                    └───────┬────────┘                 └────────────┬─────────────┘
                            │ 1433                                  │ 1433
  ──────────────────────────┼───────────────────────────────────────┼──────────── no internet route
  Isolated data     ┌───────▼───────────────────────────────────────▼─────┐
  subnets           │   Amazon RDS for SQL Server (Multi-AZ in prod)      │
                    │   KMS-encrypted · password managed in Secrets Mgr   │
                    └─────────────────────────────────────────────────────┘

  Cross-cutting: KMS CMK · S3 (artifacts, ALB logs) · VPC Flow Logs · CloudWatch alarms → SNS · SSM Session Manager
```

### What gets provisioned

| Area | Resources | Key design decisions |
|---|---|---|
| **Network** (`modules/network`) | VPC, 3 subnet tiers × 2–3 AZs, IGW, NAT, route tables, S3 gateway endpoint, VPC flow logs | DB tier has **no internet route**; one NAT per AZ in prod for HA |
| **Security** (`modules/security`) | Security groups for ALB, front-ends, controller, database | Implements the OutSystems port matrix (443, 12000, 12001, 5672, 1433). **No RDP/WinRM**: admins use SSM |
| **Storage** (`modules/storage`) | Artifacts bucket (SSE-KMS) and logs bucket (SSE-S3) | Public access blocked, versioned, TLS-only bucket policies, log lifecycle |
| **Database** (`modules/database`) | RDS SQL Server SE/EE, subnet group, enhanced monitoring | Encrypted, private, `CI_AS` collation (OutSystems needs case-insensitive), master password **generated and rotated by RDS** in Secrets Manager, Multi-AZ and deletion protection in prod |
| **Platform** (`modules/platform`) | ALB, listeners and rules, target group, WAFv2, controller EC2, front-end launch template and ASG, CPU target-tracking, IAM role/profile | IMDSv2 only, encrypted EBS, bootstrap installs IIS and OutSystems prerequisites, CloudWatch agent, optional silent Platform Server install |
| **Monitoring** (`modules/monitoring`) | SNS topic, log groups, 9 CloudWatch alarms | Covers ALB 5xx, unhealthy hosts, latency, front-end CPU, controller status checks, RDS CPU, storage and memory |
| **Encryption** (`kms.tf`) | Customer-managed KMS key and alias | Rotation on; used by RDS, Secrets Manager, S3, Logs, SNS |

---

## 2. Repository layout

```
.
├── main.tf / variables.tf / outputs.tf / kms.tf / versions.tf   # root module (one environment)
├── environments/
│   ├── dev.tfvars  test.tfvars  prod.tfvars  lifetime.tfvars    # per-environment sizing
│   └── backend.hcl.example                                       # remote state (S3 + DynamoDB lock)
├── modules/
│   ├── network/  security/  storage/  database/  monitoring/
│   └── platform/  (alb.tf, waf.tf, compute.tf, iam.tf, templates/bootstrap.ps1.tftpl)
├── tests/
│   ├── mocks/aws.tfmock.hcl               # shared fake AWS data for offline tests
│   ├── network|security|database|platform|storage_monitoring.tftest.hcl   # unit tests
│   ├── root.tftest.hcl                    # whole-stack wiring + input validation
│   ├── policy/environment_policy.tftest.hcl   # policy-as-code per tfvars
│   ├── integration/                       # real AWS deploy → verify → destroy
│   └── smoke/smoke-test.ps1               # post-deployment HTTP/TLS checks
├── scripts/run-tests.ps1                  # run the whole offline pipeline locally
├── .github/workflows/iac-ci.yml           # CI pipeline
├── .tflint.hcl  .checkov.yaml
```

---

## 3. Deploying

**Prerequisites:** Terraform ≥ 1.7, AWS credentials, an S3 state bucket and DynamoDB lock table, and an ACM certificate in the target region.

```powershell
# 1. Remote state for the environment
Copy-Item environments/backend.hcl.example environments/dev.backend.hcl   # then edit it
terraform init -backend-config=environments/dev.backend.hcl

# 2. Set the real ACM certificate ARN in environments/dev.tfvars, then:
terraform plan  -var-file=environments/dev.tfvars -out dev.tfplan
terraform apply dev.tfplan
```

Repeat for `test`, `prod` and `lifetime`. Each one uses its own backend key and tfvars file.

### After `terraform apply`: OutSystems configuration

1. Upload the OutSystems Platform Server installer to the `artifacts_bucket` output and set
   `platform_installer_s3_key`. New servers then install it silently at boot. You can also install it manually over SSM.
2. Get the DB master credentials from the secret in the `db_master_secret_arn` output.
3. On the controller, run the **OutSystems Configuration Tool**. Point it at the `db_endpoint` output and let it create
   the Platform, Session and Logging catalogs. Then register the front-ends; their bootstrap records the controller IP
   under `HKLM:\SOFTWARE\OutSystemsBootstrap`.
4. Open Service Center through SSM using the `service_center_tunnel_command` output. No RDP and no public exposure are needed:
   ```powershell
   aws ssm start-session --target <controller-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=443,localPortNumber=8443
   # browse https://localhost:8443/ServiceCenter
   ```
5. Install the license, register the environment in **LifeTime**, and deploy `HousingInsights_integration` →
   `HousingInsights_core` → `SingaporeHousingInsights` (consumer modules after producers).
6. Point your DNS name (the one on the ACM certificate) at the `alb_dns_name` output and run the smoke test.

---

## 4. Automated testing

The tests are layered, from fast and free to slow and realistic:

| # | Layer | Tool | Needs AWS? | What it proves |
|---|---|---|---|---|
| 1 | Formatting | `terraform fmt -check` | No | Consistent style |
| 2 | Static validation | `terraform validate` | No | Syntax, types, references |
| 3 | Linting | `tflint` + AWS ruleset | No | Invalid instance types, deprecated syntax, undocumented variables |
| 4 | Security / compliance scan | `checkov` | No | CIS / AWS best practices. Every skipped check is justified in `.checkov.yaml` |
| 5 | **Unit tests** | `terraform test` + `mock_provider` | No | 35 assertions on each module's behaviour (see below) |
| 6 | **Policy tests** | `terraform test` on each `environments/*.tfvars` | No | Prod is HA (Multi-AZ, NAT per AZ, ≥2 front-ends), WAF and alarms on, cert in the right region, all 3 modules hosted |
| 7 | **Integration tests** | `terraform test` against real AWS | Yes (costs money) | Deploys a throwaway stack, checks the live RDS, ALB and ASG through AWS APIs, checks `/ServiceCenter` returns 403 over HTTPS, then **destroys** the stack |
| 8 | **Smoke tests** | `tests/smoke/smoke-test.ps1` | Deployed env | HTTP→HTTPS 301, TLS 1.0/1.1 refused and 1.2 accepted, admin consoles blocked, `SingaporeHousingInsights` responds, no version disclosure |

### Highlights from the unit tests

- **Network:** 3 tiers per AZ with a fixed CIDR plan, no public IP auto-assignment, the **data tier has no internet route**, one NAT per AZ when HA is on, flow logs capture ALL traffic and are encrypted.
- **Security:** only the ALB accepts traffic from the internet, and only on 80/443. **SSH, RDP and WinRM are never opened.** The DB accepts only 1433 from the platform SGs and has no egress. The OutSystems ports 12000, 12001 and 5672 are wired between the right roles.
- **Database:** encrypted with the CMK, not public, password managed by RDS, Multi-AZ and deletion protection in prod, final snapshot, `CI_AS` collation. **SQL Express is rejected.**
- **Platform:** HTTP redirects to HTTPS, TLS 1.3 policy, invalid headers dropped, access logs on, **/ServiceCenter and /LifeTime return 403** unless the source is a management CIDR (the allow rule is evaluated before the deny rule), IMDSv2, encrypted EBS, role-specific bootstrap, ASG behind the ALB in private subnets, WAF attached when enabled, IAM without wildcard resources, inconsistent ASG sizes rejected.
- **Root:** all modules wire together; only `SingaporeHousingInsights` is exposed as a URL; `core` and `integration` are registered with the correct layer. Invalid inputs are rejected (environment, project name, single AZ, `0.0.0.0/0` management access, bad certificate ARN, bad CIDR, unknown module layer).

The tests also catch real mistakes: making the database `publicly_accessible = true` immediately fails
`production_database_is_secure_and_resilient`.

### Running the tests

```powershell
# Everything offline (fmt, validate, tflint/checkov if installed, unit and policy tests)
./scripts/run-tests.ps1

# Or individually
terraform init -backend=false
terraform test                                                     # unit tests
terraform test -test-directory=tests/policy -var-file=environments/prod.tfvars

# Real AWS integration test (creates and destroys resources)
terraform init -backend=false -test-directory=tests/integration
terraform test -test-directory=tests/integration -var="acm_certificate_arn=arn:aws:acm:ap-southeast-1:<acct>:certificate/<id>"

# After deployment
./tests/smoke/smoke-test.ps1 -BaseUrl https://housing.example.com
```

### Continuous integration (`.github/workflows/iac-ci.yml`)

```
pull request / push to main
   └─ static-analysis (fmt, validate, tflint, checkov)
        ├─ unit-tests (mocked AWS)
        └─ environment-policy  [matrix: dev, test, prod, lifetime]
             └─ integration-tests (manual workflow_dispatch only, uses AWS OIDC role)
```

For the integration job, set the repository secrets `AWS_TEST_ROLE_ARN` (an IAM role trusted for GitHub OIDC) and `TEST_ACM_CERTIFICATE_ARN`.

---

## 5. Environment sizing

| | dev | test | prod | lifetime |
|---|---|---|---|---|
| AZs | 2 | 2 | 3 | 2 |
| NAT gateways | 1 | 1 | 3 (one per AZ) | 1 |
| Controller | t3.xlarge | m6i.large | m6i.xlarge | m6i.large |
| Front-ends (min/desired/max) | 1/1/2 t3.large | 2/2/3 m6i.large | 2/3/6 m6i.xlarge | 1/1/1 m6i.large |
| RDS | db.t3.xlarge, single-AZ | db.m6i.large, single-AZ | db.m6i.xlarge, **Multi-AZ** | db.m6i.large |
| Backups | 7 days | 7 days | 30 days | 14 days |
| WAF | off | on | on | on |
| Deletion protection | off | off | **on** | off |

---

## 6. Assumptions and limitations

- **Self-managed OutSystems 11** (not OutSystems Cloud or ODC, where OutSystems runs the infrastructure).
- The OutSystems installer and license are proprietary. They are **not** stored in this repository; upload the installer to the artifacts bucket yourself.
- Configuration Tool settings (catalogs, `server.hsconf`, front-end registration) are done once after provisioning, as described in section 3.
- Front-end auto-scaling: new instances still have to be registered with the controller. Automate this with an SSM Run Command or ASG lifecycle hook if you need fully elastic scaling.
- The ACM certificate ARNs, alarm e-mail and management CIDRs in `environments/*.tfvars` are **placeholders**.
- Default region is `ap-southeast-1` (Singapore), close to the data.gov.sg API and the users.
