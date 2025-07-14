/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if */
/* eslint-disable no-inner-declarations, no-undef, import/no-unresolved */
import { expect } from "chai";
import path = require("path");
import fs = require("fs");
import { utils } from "ffjavascript";
import { logger } from "../../src/logger";
import * as dotenv from "dotenv";
dotenv.config({ path: path.resolve(__dirname, "../../.env") });
import { ethers, upgrades } from "hardhat";
import { PolygonRollupManagerPessimistic, PolygonZkEVMBridgeV2 } from "../../typechain-types";
import { genTimelockOperation, verifyContractEtherscan, decodeScheduleData, getGitInfo } from "../utils";
import { checkParams, getProviderAdjustingMultiplierGas, getDeployerFromParameters } from "../../src/utils";

const pathOutputJson = path.join(__dirname, "./upgrade_output.json");

const upgradeParameters = require("./upgrade_parameters.json");

async function main() {
    /*
     * Check upgrade parameters
     * Check that every necessary parameter is fulfilled
     */
    const mandatoryUpgradeParameters = ["rollupManagerAddress", "aggLayerGatewayAddress", "timelockDelay", "tagSCPreviousVersion"];
    checkParams(upgradeParameters, mandatoryUpgradeParameters);

    const { rollupManagerAddress, timelockDelay, aggLayerGatewayAddress, tagSCPreviousVersion, unsafeSkipStorageCheck } = upgradeParameters;
    const salt = upgradeParameters.timelockSalt || ethers.ZeroHash;

    // Load onchain parameters
    let polygonRMPreviousFactory = await ethers.getContractFactory("PolygonRollupManagerPessimistic");
    const rollupManagerPessimisticContract = (await polygonRMPreviousFactory.attach(
        rollupManagerAddress
    )) as PolygonRollupManagerPessimistic;

    const globalExitRootManagerAddress = await rollupManagerPessimisticContract.globalExitRootManager();
    const polAddress = await rollupManagerPessimisticContract.pol();
    const bridgeAddress = await rollupManagerPessimisticContract.bridgeAddress();

    // Load provider
    const currentProvider = getProviderAdjustingMultiplierGas(upgradeParameters, ethers);

    // Load deployer
    const deployer = await getDeployerFromParameters(currentProvider, upgradeParameters, ethers);
    logger.info(`Deploying implementation with: ${deployer.address}`);

    const proxyAdmin = await upgrades.admin.getInstance();

    // Assert correct admin
    expect(await upgrades.erc1967.getAdminAddress(rollupManagerAddress as string)).to.be.equal(proxyAdmin.target);

    const timelockAddress = await proxyAdmin.owner();

    // Load timelock
    const timelockContractFactory = await ethers.getContractFactory("PolygonZkEVMTimelock", deployer);
    const timelockContract = await timelockContractFactory.attach(timelockAddress);

    // Prepare upgrades

    // Upgrade to rollup manager v3
    const PolygonRollupManagerFactory = await ethers.getContractFactory("PolygonRollupManager", deployer);
    const implRollupManager = await upgrades.prepareUpgrade(rollupManagerAddress, PolygonRollupManagerFactory, {
        constructorArgs: [globalExitRootManagerAddress, polAddress, bridgeAddress, aggLayerGatewayAddress],
        unsafeAllow: ["constructor"],
    });

    logger.info("#######################\n");
    logger.info(`Polygon rollup manager implementation deployed at: ${implRollupManager}`);

    await verifyContractEtherscan(implRollupManager as string, [globalExitRootManagerAddress, polAddress, bridgeAddress, aggLayerGatewayAddress]);

    const operationRollupManager = genTimelockOperation(
        proxyAdmin.target,
        0, // value
        proxyAdmin.interface.encodeFunctionData("upgradeAndCall", [
            rollupManagerAddress,
            implRollupManager,
            PolygonRollupManagerFactory.interface.encodeFunctionData("initialize", []),
        ]), // data
        ethers.ZeroHash, // predecessor
        salt // salt
    );

    // Upgrade bridge
    const bridgeFactory = await ethers.getContractFactory("PolygonZkEVMBridgeV2", deployer);
    let impBridge;
    if (unsafeSkipStorageCheck === true) {
        logger.warn("Unsafe skip storage check is enabled, this may lead to issues if the storage layout has changed.");
        impBridge = await upgrades.prepareUpgrade(bridgeAddress, bridgeFactory, {
            unsafeAllow: ["constructor", "missing-initializer", "missing-initializer-call"],
            unsafeSkipStorageCheck: true,
        }) as string;
    } else {
        impBridge = await upgrades.prepareUpgrade(bridgeAddress, bridgeFactory, {
            unsafeAllow: ["constructor", "missing-initializer", "missing-initializer-call"],
        }) as string;
    }

    logger.info("#######################\n");
    logger.info(`Polygon bridge implementation deployed at: ${impBridge}`);

    await verifyContractEtherscan(impBridge, []);

    // Verify bytecodeStorer
    const bridgeContract = bridgeFactory.attach(impBridge) as PolygonZkEVMBridgeV2;
    const bytecodeStorerAddress = await bridgeContract.wrappedTokenBytecodeStorer();
    await verifyContractEtherscan(bytecodeStorerAddress, []);
    logger.info("#######################\n");
    logger.info(`wrappedTokenBytecodeStorer deployed at: ${bytecodeStorerAddress}`);

    // Verify wrappedTokenBridgeImplementation
    const wrappedTokenBridgeImplementationAddress = await bridgeContract.getWrappedTokenBridgeImplementation();
    await verifyContractEtherscan(wrappedTokenBridgeImplementationAddress, []);
    logger.info("#######################\n");
    logger.info(`wrappedTokenBridge Implementation deployed at: ${wrappedTokenBridgeImplementationAddress}`);

    const operationBridge = genTimelockOperation(
        proxyAdmin.target,
        0, // value
        proxyAdmin.interface.encodeFunctionData("upgradeAndCall", [
            bridgeAddress,
            impBridge,
            bridgeFactory.interface.encodeFunctionData("initialize()", [])
        ]), // data
        ethers.ZeroHash, // predecessor
        salt // salt
    );

    // Upgrade PolygonZkEVMGlobalExitRootV2
    const globalExitRootManagerFactory = await ethers.getContractFactory("PolygonZkEVMGlobalExitRootV2", deployer);
    const globalExitRootManagerImp = await upgrades.prepareUpgrade(globalExitRootManagerAddress, globalExitRootManagerFactory, {
        constructorArgs: [rollupManagerAddress, bridgeAddress],
        unsafeAllow: ["constructor", "missing-initializer"],
    });
    logger.info("#######################\n");
    logger.info(`Polygon global exit root manager implementation deployed at: ${globalExitRootManagerImp}`);

    await verifyContractEtherscan(globalExitRootManagerImp as string, [rollupManagerAddress, bridgeAddress]);

    const operationGlobalExitRoot = genTimelockOperation(
        proxyAdmin.target,
        0, // value
        proxyAdmin.interface.encodeFunctionData("upgrade", [globalExitRootManagerAddress, globalExitRootManagerImp]), // data
        ethers.ZeroHash, // predecessor
        salt // salt
    );

    // Schedule operation
    const scheduleData = timelockContractFactory.interface.encodeFunctionData("scheduleBatch", [
        [operationRollupManager.target, operationBridge.target, operationGlobalExitRoot.target],
        [operationRollupManager.value, operationBridge.value, operationGlobalExitRoot.value],
        [operationRollupManager.data, operationBridge.data, operationGlobalExitRoot.data],
        ethers.ZeroHash, // predecessor
        salt, // salt
        timelockDelay,
    ]);

    logger.info("Scheduling timelock batch operation");
    const scheduleTx = await timelockContract.connect(deployer).scheduleBatch(
        [operationRollupManager.target, operationBridge.target, operationGlobalExitRoot.target],
        [operationRollupManager.value, operationBridge.value, operationGlobalExitRoot.value],
        [operationRollupManager.data, operationBridge.data, operationGlobalExitRoot.data],
        ethers.ZeroHash, // predecessor
        salt,
        timelockDelay
    );
    await scheduleTx.wait();
    logger.info(`Timelock batch scheduled in tx: ${scheduleTx.hash}`);

    // Generate execute data
    const executeData = timelockContractFactory.interface.encodeFunctionData("executeBatch", [
        [operationRollupManager.target, operationBridge.target, operationGlobalExitRoot.target],
        [operationRollupManager.value, operationBridge.value, operationGlobalExitRoot.value],
        [operationRollupManager.data, operationBridge.data, operationGlobalExitRoot.data],
        ethers.ZeroHash, // predecessor
        salt,
    ]);

    // Check if operation is ready
    const operationId = await timelockContract.hashOperationBatch(
        [operationRollupManager.target, operationBridge.target, operationGlobalExitRoot.target],
        [operationRollupManager.value, operationBridge.value, operationGlobalExitRoot.value],
        [operationRollupManager.data, operationBridge.data, operationGlobalExitRoot.data],
        ethers.ZeroHash,
        salt
    );
    const isOperationReady = await timelockContract.isOperationReady(operationId);

    if (!isOperationReady) {
        logger.warn(`Timelock operation ${operationId} is not ready. Waiting for ${timelockDelay} seconds delay.`);
        logger.info(`Please execute the operation manually using the following details after ${timelockDelay} seconds:`);
        logger.info(`Timelock Contract: ${timelockAddress}`);
        logger.info(`Execute Data: ${executeData}`);
        logger.info(`You can call executeBatch on the timelock contract after the delay using the deployer account: ${deployer.address}`);
    } else {
        logger.info("Executing timelock batch operation");
        const executeTx = await timelockContract.connect(deployer).executeBatch(
            [operationRollupManager.target, operationBridge.target, operationGlobalExitRoot.target],
            [operationRollupManager.value, operationBridge.value, operationGlobalExitRoot.value],
            [operationRollupManager.data, operationBridge.data, operationGlobalExitRoot.data],
            ethers.ZeroHash, // predecessor
            salt
        );
        await executeTx.wait();
        logger.info(`Timelock batch executed in tx: ${executeTx.hash}`);

        // Verify new implementations
        const newRollupManagerImpl = await upgrades.erc1967.getImplementationAddress(rollupManagerAddress);
        expect(newRollupManagerImpl).to.equal(implRollupManager, "Rollup Manager proxy not upgraded to new implementation");
        logger.info(`Rollup Manager proxy upgraded to: ${newRollupManagerImpl}`);

        const newBridgeImpl = await upgrades.erc1967.getImplementationAddress(bridgeAddress);
        expect(newBridgeImpl).to.equal(impBridge, "Bridge proxy not upgraded to new implementation");
        logger.info(`Bridge proxy upgraded to: ${newBridgeImpl}`);

        const newGlobalExitRootImpl = await upgrades.erc1967.getImplementationAddress(globalExitRootManagerAddress);
        expect(newGlobalExitRootImpl).to.equal(globalExitRootManagerImp, "Global Exit Root proxy not upgraded to new implementation");
        logger.info(`Global Exit Root proxy upgraded to: ${newGlobalExitRootImpl}`);
    }

    // Get current block number
    const blockNumber = await ethers.provider.getBlockNumber();
    const outputJson = {
        tagSCPreviousVersion: tagSCPreviousVersion,
        gitInfo: getGitInfo(),
        scheduleData,
        executeData,
        timelockContractAddress: timelockAddress,
        scheduleTxHash: scheduleTx.hash,
        implementationDeployBlockNumber: blockNumber,
        deployedContracts: {
            rollupManagerImplementation: implRollupManager,
            bridgeImplementation: impBridge,
            globalExitRootManagerImplementation: globalExitRootManagerImp,
            wrappedTokenBytecodeStorer: bytecodeStorerAddress,
            wrappedTokenBridgeImplementation: wrappedTokenBridgeImplementationAddress,
        }
    };

    // Decode the scheduleData for better readability
    const objectDecoded = await decodeScheduleData(scheduleData, proxyAdmin);
    outputJson.decodedScheduleData = objectDecoded;

    fs.writeFileSync(pathOutputJson, JSON.stringify(utils.stringifyBigInts(outputJson), null, 2));
}

main().catch((e) => {
    logger.error(e);
    process.exit(1);
});