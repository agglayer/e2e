# 🧭 Attaching Your Existing Network to Polygon AggLayer

This guide outlines the steps to integrate your blockchain network with Polygon's AggLayer. It specifies which actions are performed by **Polygon** and which require **your input**.

> **Note:** For reference, the full automation script is available here: [run.sh](https://github.com/agglayer/e2e/blob/scenario/attach_outpost/scenarios/attach_outpost/run.sh)

---

## 🛠️ Prerequisites

Before proceeding, ensure you have the following:

- **Rollup details:** Basic information about your network, as Chain ID, name, RPCs, trusted Sequencer, etc.
- **Access to required repositories:** You'll need to download, compile/run components from agglayer-contracts, aggkit, bridge-service.
- **Infra provider:** You'll need to deploy Linux-based instances for these services to run.

---

## 🔄 Overview of the Integration Process

1. **Add AggChain ro AggLayer** — *Performed by Polygon*
2. **Deploy L2 contracts** — *Performed by User*
3. **Run AggKit** — *Performed by User*
4. **Run Bridge Service** — *Performed by User*

---

## 📝 Hig Level Instructions

### 1. Polygon: Add AggChain to RollupManager

Polygon will perform the initial setup, which includes:

- Creating new Rollup Type if required.
- Adding your Rollup to the RollupManager

> 💡 **No action required from your side at this stage. This action has no dependencies and no impact, so it can be done at any point.**

---

### 2. User: Deploy Agglayer contracts on your Rollup

You need to deploy Agglayer contracts on the Rollup.

- **BridgeL2SovereignChain** — Unique identifier for your network.
- **GlobalExitRootManagerL2SovereignChain** — URL for accessing your node.

> 💡 **This action has no dependencies and no impact, so it can be done at any point.**

---

### 3. User: Run AggKit

Deploy AggKit component on your infrastructure (AggSender + AggOracle), it will be responsible for:

- Injecting GER updates.
- Send certificates to AggLayer.

> 💡 **This step needs to be done after all previous steps are already done.**

---

### 4. User: Run Bridge service

Deploy Bridge-service component on your infrastructure.

- CLI/UI bridging tools will rely on this component

> 💡  **This step also needs to be done after steps 1 and 2.**

---

## ✅ Completion

Once all steps are done, your network is part of Polygon's AggLayer. You can now utilize advanced interoperability features and routing services.

---

## 📎 Additional Resources

- **Automation Script:** [run.sh](https://github.com/agglayer/e2e/blob/scenario/attach_outpost/scenarios/attach_outpost/run.sh)
- **Polygon Documentation:** [https://docs.polygon.technology/](https://docs.polygon.technology/)
- **Support Portal:** [https://support.polygon.technology/](https://support.polygon.technology/)

---

For help or questions, please reach out to your Polygon technical contact or open a support request.
