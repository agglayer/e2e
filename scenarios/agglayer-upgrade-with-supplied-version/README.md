# Agglayer Upgrade/Downgrade Automation

This repo contains e2e test scenario to automate **Agglayer image upgrade and downgrade** while running rollup testnets inside **Kurtosis**.

It is designed to:

- Bootstrap multiple rollup flavors ( e.g both opgeth and erigon stack ) into the **same Kurtosis enclave**.
- Start Agglayer using a **FROM_TAG** version.
- Upgrade Agglayer to a **TO_TAG** version.
- Optionally downgrade back to the original **FROM_TAG** for validation.
- Cleanly tear down the setup using:
  ```bash
  kurtosis enclave rm cdk --force
  ```

- Test file: https://github.com/agglayer/e2e/actions/runs/17996146694/workflow?pr=168
- Reference: https://github.com/agglayer/e2e/blob/main/tests/lxly/lxly.bats
- Branch-seen: (https://github.com/agglayer/e2e/blob/jihwan/multi-chain-bridge-workflow/tests/lxly/multi-chain-bridge.bats)
- Branch-sug: https://github.com/agglayer/e2e/blob/main/tests/lxly/lxly.bats
- Branch-seen: jihwan/multi-chain-bridge-workflow 
- Kurtosis-branch: jhilliard/aggsender-validator-committee
- . ./common.sh && _setup_vars
# shellcheck source=./lxly.sh
# source "$SCRIPT_DIR/lxly.sh"
# main native
---

##  Scripts

- `run.sh`
  Main orchestration script. Handles bootstrap, upgrade, and optional downgrade.
    - **Create the .env file:**
    ```bash
    cp env.example .env
    ```

  - **Upgrade usage:**
    ```bash
    ./run.sh FROM_TAG TO_TAG
    ```

    example

    ```bash
    ./run.sh 0.3.4 0.3.5
    ```

  - **Downgrade usage:**
    ```bash
    ./run.sh FROM_TAG TO_TAG downgrade
    ```
    example

    ```bash
    ./run.sh  0.3.5 0.3.4  downgrade
    ```
##  Arguments & Descriptions

| Argument               | Required | Description |
|------------------------|----------|-------------|
| `<FROM_TAG>`           |    Yes   | Docker image tag to start with (e.g., `0.3.4`)|
| `<TO_TAG>`             |    Yes   | Docker image tag to upgrade to (e.g., `0.3.5`)|
| `[ACTION]`             |     No   | Optional: set to `downgrade` to  downgrade back to `<FROM_TAG>` after upgrade |

---



````
