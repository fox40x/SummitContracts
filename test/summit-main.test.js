const { expect } = require("chai");
const { ethers, UniswapV2Deployer } = require("hardhat");
const { MaxUint256 } = ethers.constants;
const { parseEther, formatEther, formatUnits } = require('ethers/lib/utils');
const { BigNumber } = require("ethers");

let summit;
let router;
let signers;
let pair;
let factory;
let buyPath;
let sellPath;
let oxygen;
let owner;
let receiver;
let buyer;
let buyer2

const liquidityAmountEth = parseEther("100")
const liquidityAmountSummit = parseEther("400000000")
const initialTransferAmount = parseEther("10000000")
const contributionPercentage = 12
const magnitude = BigNumber.from("340282366920938000000000000000000000000");
const emergencySwapAndDistributeAmount = parseEther("5000000")
const buyAmount1 = parseEther('15')
const contractorGratuity = 2;
const climberAwarenessFund = 1;
const communityContribution = 9;
const totalContribution = 12;
const contractorAddress = '0x1f4b51737FDa4231Ca06C195b6Cc64f862D10E13';
const climberAwarenessAddress = '0x2082059A610E8A82DD19EFfdfAF7601048c3095f';
const swapThreshold = parseEther("5000000");

describe("Multiple buys", function () {
    let buyer;

    before(async function () {
        signers = await ethers.getSigners();
        owner = signers[0];
        receiver = signers[1];
        buyer = signers[3];
        buyer2 = signers[4];

        // Deploy Uniswap contracts
        const [deployer] = await ethers.getSigners();
        const { weth9: _weth9, factory: _factory, router: _router } = await UniswapV2Deployer.deploy(deployer)
        weth9 = _weth9;
        factory = _factory;
        router = _router;

        signers = await ethers.getSigners();
        buyer = signers[5];

        const Summit = await ethers.getContractFactory("Summit");
        summit = await Summit.deploy(router.address);
        await summit.deployed();

        const summitPairAddress = await summit.uniswapV2Pair();
        const Oxygen = await ethers.getContractFactory("Oxygen");
        oxygen = await Oxygen.deploy(summit.address, summitPairAddress, router.address);
        await oxygen.deployed();
        await summit.setOxygen(oxygen.address);
    });

    it('Liquidity can be added', async () => {
        await summit.approve(router.address, MaxUint256);

        await router.addLiquidityETH(
            summit.address,
            liquidityAmountSummit,
            parseEther("0"),
            parseEther("0"),
            signers[0].address,
            MaxUint256,
            {
                value: liquidityAmountEth
            }
        );

        console.log('liq added');
        const pairAddress = await factory.getPair(summit.address, weth9.address);
        pair = await ethers.getContractAt('IUniswapV2Pair', pairAddress);
        buyPath = [weth9.address, summit.address];
        sellPath = [summit.address, weth9.address];

        const pairBalanceEth = await weth9.balanceOf(pairAddress);
        const pairBalanceSummit = await summit.balanceOf(pairAddress);

        expect(pairBalanceEth).to.equal(liquidityAmountEth);
        expect(pairBalanceSummit).to.equal(liquidityAmountSummit);
    });

    it('Owner can transfer tokens', async () => {
        await summit.transfer(receiver.address, initialTransferAmount);
        const receiverBalance = await summit.balanceOf(receiver.address);
        expect(receiverBalance).to.equal(initialTransferAmount);
    });

    it('Is not tradable before setting start time', async () => {
        const summitAsTransferrer = await summit.connect(receiver);
        await expect(summitAsTransferrer.transfer(signers[3].address, initialTransferAmount)).to.be.revertedWith('The game has not started');
    });

    it('Cannot set start time once start time has passed', async () => {
        const block = await ethers.provider.getBlock("latest");
        await expect(summit.setGameStartTime(block.timestamp - 100)).to.be.revertedWith('Start must be in the future');
    });
    
    it('Game start time can be set in the future', async () => {
        const block = await ethers.provider.getBlock("latest");
        await expect(summit.setGameStartTime(block.timestamp + 100)).to.not.be.reverted;
    })

    it('Is transferrable after start time has passed', async () => {
        await ethers.provider.send("evm_increaseTime", [5000]);
        await ethers.provider.send("evm_mine");
        const summitAstransferrer = await summit.connect(receiver);
        await expect(summitAstransferrer.transfer(signers[3].address, initialTransferAmount)).to.not.be.reverted;
    })

    it('Takes a tax on transfer', async () => {
        const balance = await summit.balanceOf(signers[3].address);
        const expectedTax = initialTransferAmount.mul(contributionPercentage).div(100);
        const expectedAmount = initialTransferAmount.sub(expectedTax);
        expect(balance).to.equal(expectedAmount);

        const contractBalance = await summit.balanceOf(summit.address);
        expect(contractBalance).to.equal(expectedTax);
    })

    it ('Takes the correct tax on buy', async () => {
        const routerAsBuyer = await router.connect(buyer);
        const expectedAmountOut = await router.getAmountsOut(buyAmount1, buyPath);
        const expectedTax = expectedAmountOut[1].mul(contributionPercentage).div(100);
        await expect(routerAsBuyer.swapExactETHForTokensSupportingFeeOnTransferTokens(
            0,
            buyPath,
            buyer.address,
            ethers.constants.MaxUint256,
            { value: buyAmount1 }
        )).to.not.be.reverted;

        const buyerbalanceAfter = await summit.balanceOf(buyer.address);
        const expectedBuyerBalanceAfter = expectedAmountOut[1].sub(expectedTax);
        expect(buyerbalanceAfter).to.equal(expectedBuyerBalanceAfter);
    })

    it('Mints the correct oxygen', async () => {
        const tokenAmount = await router.getAmountsOut(buyAmount1, buyPath);
        const [reserve0, reserve1] = await pair.getReserves();
        const tokenReserve = summit.address < weth9.address ? reserve0 : reserve1;
        const ethReserve = summit.address < weth9.address ? reserve1 : reserve0;
        const ethInput = await router.getAmountIn(tokenAmount[1], ethReserve, tokenReserve);
        const tokenPrice = (ethReserve.add(ethInput)).mul(magnitude).div(tokenReserve.sub(tokenAmount[1]));
        const expectedOxygen = ethInput.mul(tokenPrice).div(magnitude);

        const routerAsBuyer = await router.connect(buyer2);

        await expect(routerAsBuyer.swapExactETHForTokensSupportingFeeOnTransferTokens(
            0,
            buyPath,
            buyer2.address,
            ethers.constants.MaxUint256,
            { value: buyAmount1 }
        )).to.not.be.reverted;

        const oxygenBalance = await oxygen.balanceOf(buyer2.address);
        expect(oxygenBalance).to.equal(expectedOxygen);
    });
    
    it('Emergency swap works', async () => {
        const amountOut = await router.getAmountsOut(emergencySwapAndDistributeAmount, sellPath);
        const EthAmountOut = amountOut[1];

        const climberAwarenessAmount = EthAmountOut.mul(climberAwarenessFund).div(totalContribution);
        const contractorAmount = EthAmountOut.mul(contractorGratuity).div(totalContribution);
        const communityAmount = EthAmountOut.sub(climberAwarenessAmount).sub(contractorAmount);
        
        await summit.emergencySwapAndDistribute(emergencySwapAndDistributeAmount);

        const oxygenContractEthBalance = await ethers.provider.getBalance(oxygen.address);
        expect(oxygenContractEthBalance).to.equal(communityAmount);

        const climberAwarenessEthBalance = await ethers.provider.getBalance(climberAwarenessAddress);
        expect(climberAwarenessEthBalance).to.equal(climberAwarenessAmount);

        const contractorEthBalance = await ethers.provider.getBalance(contractorAddress);
        expect(contractorEthBalance).to.equal(contractorAmount);
    });

    it('Selling tokens sells tokens from summit contract', async () => {
        const oxygenEthereBalance = await ethers.provider.getBalance(oxygen.address);
        const summitTokenBalance = await summit.balanceOf(summit.address);
        console.log('summit balance: ', formatEther(summitTokenBalance));

        const routerAsSeller = await router.connect(buyer2);
        
        const summitAsSeller = await summit.connect(buyer2);
        await summitAsSeller.approve(router.address, MaxUint256);
        
        const taxOnSell = swapThreshold.mul(contributionPercentage).div(100);

        const tokenBalance = await oxygen.balanceOf(buyer2.address);
        await routerAsSeller.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            sellPath,
            buyer2.address,
            ethers.constants.MaxUint256
        );

        const oxygenEtherBalanceAfter = await ethers.provider.getBalance(oxygen.address);
        const summitTokenBalanceAfter = await summit.balanceOf(summit.address);

        expect(oxygenEtherBalanceAfter).to.be.gt(oxygenEthereBalance);
        // expect(summitTokenBalanceAfter).to.equal(summitTokenBalance.sub(swapThreshold)).add(taxOnSell);
    })
    
    it('Keep climbing works', async () => {
        const oxygenAsBuyer2 = await oxygen.connect(buyer2);
        const gameState = await oxygen.gameState(buyer2.address);
        console.log('game state: ', gameState);
        await oxygenAsBuyer2.keepClimbing(0);
        const gameStateAfter = await oxygen.gameState(buyer2.address);
        console.log('game state after: ', gameStateAfter);
    })
})
