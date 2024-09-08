const { expect } = require("chai");
const { ethers, UniswapV2Deployer } = require("hardhat");
const { parseEther, formatEther } = require('ethers/lib/utils');

const PRESALE_RECEIVER_ADDRESS = '0x3f70594f9163A6AcEA60207776d80ae1ED3a0436';
const MIN_PURCHASE_AMOUNT = parseEther('373333.3333');
const MAX_PURCHASE_AMOUNT = parseEther('3733333.333');
const TOKEN_PER_ETH = parseEther('3733333.333');
const TOKEN_ALLOCATION = parseEther('560000000');
const VESTING_START = 1788234953;
const VESTING_DURATION = 1209600;

const secondsPerWeek = 604800;
const fullVestingDuration = secondsPerWeek * 2;

const VESTING_START_TIME = 1788234953;
const VESTING_QUARTER_TIME = VESTING_START_TIME + (fullVestingDuration / 4);
const VESTING_THREE_QUARTER_TIME = VESTING_START_TIME + fullVestingDuration - (fullVestingDuration / 4);
const VESTING_FULL_TIME = VESTING_START_TIME + fullVestingDuration;

let summit;
let router;
let signers;
let oxygen;
let vestedSale;
let whiteList = [];

describe("Vested Sale", function () {
    let owner;
    let zeroPointOneEthBuyer;
    let zeroPointNineEthBuyer;
    let summit;
    let vesting;

    before(async function () {
        signers = await ethers.getSigners();
        owner = signers[0]
        zeroPointOneEthBuyer = signers[159];
        zeroPointNineEthBuyer = signers[160];

        const { weth9: _weth9, factory: _factory, router: _router } = await UniswapV2Deployer.deploy(owner)
        router = _router;

        for (let index = 10; index < 160; index++) {
            const element = signers[index];
            whiteList.push(element.address)
        }

        const Summit = await ethers.getContractFactory("Summit");
        summit = await Summit.deploy(router.address);
        await summit.deployed();

        const summitPairAddress = await summit.uniswapV2Pair();
        const Oxygen = await ethers.getContractFactory("Oxygen");

        oxygen = await Oxygen.deploy(summit.address, summitPairAddress, router.address);
        await oxygen.deployed();
        
        await summit.setOxygen(oxygen.address);
        
        const VestedSale = await ethers.getContractFactory("VestedSale");

        vestedSale = await VestedSale.deploy(
            summit.address,
            PRESALE_RECEIVER_ADDRESS,
            MIN_PURCHASE_AMOUNT,
            MAX_PURCHASE_AMOUNT,
            TOKEN_PER_ETH,
            TOKEN_ALLOCATION,
            VESTING_START,
            VESTING_DURATION
        );

        await vestedSale.deployed();
        await summit.setOxygen(oxygen.address);
        await summit.setExcluded(vestedSale.address, true);
        await oxygen.excludeFromEth(vestedSale.address);
        await summit.transfer(vestedSale.address, parseEther('560000000'))
    })

    it("white list works", async function () {
        await expect(vestedSale.addWhitelist(whiteList)).to.not.be.reverted;

        // loop each address and expect whitelist true
        for (let index = 10; index < 160; index++) {
            const element = signers[index];
            const whiteListed = await vestedSale.whitelist(element.address);
            expect(whiteListed).to.equal(true);
        }

        const notWhitelisted = await vestedSale.whitelist(signers[8].address);
        expect(notWhitelisted).to.equal(false);
    })

    it("purchase fails with incorrect value", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[10]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('0.09')})).to.be.revertedWith('Below min purchase');
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('1.01')})).to.be.revertedWith('Exceeds max purchase');
    })

    it("purchase fails with non whiteliseted", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[8]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('1')})).to.be.revertedWith('Sender is not whitelisted');
    })

    it("purchase works", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[10]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('0.5')})).to.not.be.reverted;
    })

    it("puchase works for buyer when initial purchase was less then max", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[10]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('0.5')})).to.not.be.reverted;
    })

    it("purchase fails when max already bought", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[10]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('1')})).to.be.revertedWith('Exceeds max purchase');
    })

    it("all whitelisted buyers can purhcase", async function () {
        for (let index = 11; index < 159; index++) {
            const vestedSaleAsBuyer = await vestedSale.connect(signers[index]);
            await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('1')})).to.not.be.reverted;
        }
    })

    it("non whitelisted buyers can purchase when whitelist is turned off", async function () {
        await vestedSale.setEnforceWhitelist(false);
        const vestedSaleAsPointOneEthBuyer = await vestedSale.connect(zeroPointOneEthBuyer);
        await expect(vestedSaleAsPointOneEthBuyer.buyTokens({value: parseEther('0.1')})).to.not.be.reverted;

        const vestedSaleAsPointNineEthBuyer = await vestedSale.connect(zeroPointNineEthBuyer);
        await expect(vestedSaleAsPointNineEthBuyer.buyTokens({value: parseEther('0.9')})).to.not.be.reverted;
    })

    // all tokens are now sold out

    it("All eth is sent to owner", async function () {
        const collectorBalance = await ethers.provider.getBalance(PRESALE_RECEIVER_ADDRESS);
        expect(collectorBalance).to.equal(parseEther('150'));
    })

    it("reverts one all tokens are allocated", async function () {
        const vestedSaleAsBuyer = await vestedSale.connect(signers[162]);
        await expect(vestedSaleAsBuyer.buyTokens({value: parseEther('0.1')})).to.be.revertedWith('Exceeds total allocation');
    })

    it("vesting has no balance of oxygen", async function () {
        const oxygenBalance = await oxygen.balanceOf(vestedSale.address);
        expect(oxygenBalance).to.equal(parseEther('0'));
    })

    it("Release reverts if vesting has not started", async function () {
        const vestedSaleAsReleaser = vestedSale.connect(signers[10]);
        await expect(vestedSaleAsReleaser.releaseTokens()).to.be.revertedWith('No tokens available for release');
    })

    it("Set start time works", async function () {
        await vestedSale.setVestingStartTime(VESTING_START_TIME);
        await network.provider.send("evm_setNextBlockTimestamp", [VESTING_START_TIME]);
        await network.provider.send("evm_mine")
        const start = await vestedSale.start();
        expect(start).to.equal(VESTING_START_TIME.toString());
    })

    it("start time cannot be changed once started", async function () {
        await network.provider.send("evm_setNextBlockTimestamp", [VESTING_START_TIME + 100]);
        await expect(vestedSale.setVestingStartTime(VESTING_START_TIME + 2000)).to.be.revertedWith('Vesting has already started');
    })

    it("vests tokens correctly", async function () {
        // check that 25% is vested
        await network.provider.send("evm_setNextBlockTimestamp", [VESTING_QUARTER_TIME]);
        await network.provider.send("evm_mine")

        const zeroPointOneEthBuyerVestInfo = await vestedSale.vestingInfoByAddress(zeroPointOneEthBuyer.address);
        const zeroPointNineEthBuyerVestInfo = await vestedSale.vestingInfoByAddress(zeroPointNineEthBuyer.address);
        const OneEthBuyerVestInfo = await vestedSale.vestingInfoByAddress(signers[10].address);

        const zeroPointOneEthBuyerVestedExpectedAmount = zeroPointOneEthBuyerVestInfo.vest.tokenAmount.mul(25).div(100);
        expect(zeroPointOneEthBuyerVestInfo.vested).to.equal(zeroPointOneEthBuyerVestedExpectedAmount)

        const zeroPointNineEthBuyerVestedExpectedAmount = zeroPointNineEthBuyerVestInfo.vest.tokenAmount.mul(25).div(100);
        expect(zeroPointNineEthBuyerVestInfo.vested).to.equal(zeroPointNineEthBuyerVestedExpectedAmount)

        const OneEthBuyerVestedExpectedAmount = OneEthBuyerVestInfo.vest.tokenAmount.mul(25).div(100);
        expect(OneEthBuyerVestInfo.vested).to.equal(OneEthBuyerVestedExpectedAmount)
    })

    it("withdraws all tokens correctly", async function () {
        const vestedSaleAsReleaser = vestedSale.connect(signers[10]);
        await network.provider.send("evm_setNextBlockTimestamp", [VESTING_FULL_TIME]);
        await vestedSaleAsReleaser.releaseTokens();
        const tokenBalance = await summit.balanceOf(signers[10].address);
        expect(tokenBalance).to.equal(TOKEN_PER_ETH);
    })

    it("fails when all tokens withdrawn", async function () {
        const vestedSaleAsReleaser = vestedSale.connect(signers[10]);
        await expect(vestedSaleAsReleaser.releaseTokens()).to.be.revertedWith('No tokens available for release');
    })

    it("allocates tokens to all vesters correctly", async function () {
        for (let index = 11; index < 159; index++) {
            const vestedSaleAsBuyer = await vestedSale.connect(signers[index]);
            await vestedSaleAsBuyer.releaseTokens()
            const balance = await summit.balanceOf(signers[index].address)
            expect(balance).to.equal(TOKEN_PER_ETH)
        }

        const vestedSaleAsZeroPointOneEthBuyer = await vestedSale.connect(zeroPointOneEthBuyer);
        await vestedSaleAsZeroPointOneEthBuyer.releaseTokens();

        const vestedSaleAsZeroPointNineEthBuyer = await vestedSale.connect(zeroPointNineEthBuyer);
        await vestedSaleAsZeroPointNineEthBuyer.releaseTokens();
    })

    it("all tokens are withdrawn after last release", async function () {
        const saleContractBalance = await summit.balanceOf(vestedSale.address);
        expect(saleContractBalance).to.equal(parseEther('0.05'))
    })

})
