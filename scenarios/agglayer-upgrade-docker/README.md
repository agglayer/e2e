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

- `run-upgrade-agglayer.sh`  
  Stops/removes Kurtosis Agglayer services, updates configs, and starts Agglayer + Prover via Docker Compose.

- `run-service-update.sh`  
  Helper invoked during upgrade to update Agglayer to the target image.

- `docker-compose.yml`  
  Defines `agglayer` and `agglayer-prover` services, with images injected from `.env`.

- `assets/*.yml`  
  Base Kurtosis args-files for Validium, Rollup, and PP networks.

---


