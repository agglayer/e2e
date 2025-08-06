#   Agglayer Upgrade/Downgrade Automation

This repository contains Bash scripts to **automate Agglayer image upgrades and downgrades** within **Kurtosis rollup testnets**, attaching Agglayer services using **Docker Compose**.

---

##  Features

- Bootstrap multiple rollup flavors (**Validium**, **Rollup**, **PP**) in a single Kurtosis enclave
- Start Agglayer using a **FROM_TAG** Docker image
- Upgrade to a **TO_TAG** version
- Downgrade back to **FROM_TAG** (optional)
-   **Mandatory selection of image source**:
  - Use a **Kurtosis-supplied base image**
  - Or use a **CLI-supplied Docker image**

---


---

##  Arguments & Descriptions

| Argument               | Required | Description |
|------------------------|----------|-------------|
| `<FROM_TAG>`           |    Yes   | Docker image tag to start with (e.g., `0.3.0-rc.21`)|
| `<TO_TAG>`             |    Yes   | Docker image tag to upgrade to (e.g., `0.3.5`)|
| `<IMAGE_SOURCE_OPTION>`|    Yes   | Choose image source:<br> `k` = Kurtosis-supplied base image <br> `c` = CLI-supplied image |
| `[TEST_DOWNGRADE]`     |     No   | Optional: set to `true` to test downgrade back to `<FROM_TAG>` after upgrade |

---

##  Scripts Overview

| Script                     | Description |
|----------------------------|-------------|
| `run.sh`                   | Main orchestrator. Accepts tags, image source, and optional downgrade. |
| `run-upgrade-agglayer.sh`  | Replaces Agglayer Docker Compose stack during upgrade. |
| `run-service-update.sh`    | Updates running service to the target image. |
| `run-service-downgrade.sh` | Rolls services back to the `FROM_TAG`. |
| `docker-compose.yml`       | Defines `agglayer` and `agglayer-prover` services. Image tags are loaded from `.env`. |
| `assets/*.yml`             | Kurtosis args files for different rollup types. |

---

##  Usage

```bash
./run.sh <FROM_TAG> <TO_TAG> <IMAGE_SOURCE_OPTION> [TEST_DOWNGRADE]
