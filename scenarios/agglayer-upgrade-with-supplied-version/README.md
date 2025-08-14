# Agglayer Upgrade/Downgrade Automation

This repo contains shell scripts to automate **Agglayer image upgrades and downgrades** while running rollup testnets inside **Kurtosis** and attaching Agglayer services via **Docker Compose**.

It is designed to:

- Bootstrap multiple rollup flavors (Validium, Rollup, PP) into the **same Kurtosis enclave**.
- Start Agglayer at a **FROM_TAG** version.
- Upgrade Agglayer to a **TO_TAG** version.
- Optionally downgrade back to the original **FROM_TAG** for validation.
- Cleanly tear down the setup using:
  ```bash
  kurtosis enclave rm cdk --force

---

##  Scripts

- `run.sh`  
  Main orchestration script. Handles bootstrap, upgrade, and optional downgrade.  
  - **Upgrade usage:**  
    ```bash
    ./run.sh FROM_TAG TO_TAG
    ```
  - **Downgrade usage:**  
    ```bash
    ./run.sh FROM_TAG TO_TAG true
    ```

##  Arguments & Descriptions

| Argument               | Required | Description |
|------------------------|----------|-------------|
| `<FROM_TAG>`           |    Yes   | Docker image tag to start with (e.g., `0.3.0-rc.21`)|
| `<TO_TAG>`             |    Yes   | Docker image tag to upgrade to (e.g., `0.3.5`)|
| `[OPTION]`             |     No   | Optional: set to `true` to  downgrade back to `<FROM_TAG>` after upgrade |

---



