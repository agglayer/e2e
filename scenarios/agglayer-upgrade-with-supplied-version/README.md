# Agglayer Upgrade/Downgrade Automation

This repo contains e2e test scenario to automate **Agglayer image upgrade and downgrade** while running rollup testnets inside **Kurtosis**.

It is designed to:

- Bootstrap multiple rollup flavors ( e.g 1 Validium and  2 Rollup ) into the **same Kurtosis enclave**.
- Start Agglayer using a **FROM_TAG** version.
- Upgrade Agglayer to a **TO_TAG** version.
- Optionally downgrade back to the original **FROM_TAG** for validation.
- Cleanly tear down the setup using:
  ```bash
  kurtosis enclave rm cdk --force
  ```

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
