import { ethers } from 'hardhat';

async function main() {
    const [owner, user1, user2, user3] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = await Factory.deploy(owner.address);
    await factory.deployed()

    const ERC20 = await ethers.getContractFactory("MERC20");
    let tokenA = await ERC20.deploy("tokenA", "TA", 18);
    await tokenA.deployed();
    let tokenB = await ERC20.deploy("tokenB", "TB", 18);
    await tokenB.deployed();

    if (tokenA.address > tokenB.address) {
        const tmp = tokenA;
        tokenA = tokenB;
        tokenB = tmp;
    }

    let tx = await factory.createPair(tokenA.address, tokenB.address);
    await tx.wait();

    const pair = await ethers.getContractAt("UniswapV2Pair", await factory.getPair(tokenA.address, tokenB.address));

    console.log(" === DEPLOY === ");
    console.log("TokenA address: ", tokenA.address);
    console.log("TokenB address: ", tokenB.address);
    console.log("pair address: ", pair.address);
    

    // === МИНТИМ ТОКЕНЫ ===

    const amountA = 1000000000;
    const amountB = 100000000;
    tx = await tokenA.mint(user1.address, amountA);
    await tx.wait();
    tx = await tokenB.mint(user1.address, amountB);
    await tx.wait();
    tx = await tokenA.mint(user2.address, amountA);
    await tx.wait();
    tx = await tokenB.mint(user2.address, amountB);
    await tx.wait();
    tx = await tokenA.mint(user3.address, amountA);
    await tx.wait();
    tx = await tokenB.mint(user3.address, amountB);
    await tx.wait();

    console.log(" === BALANCES === ");
    console.log("user1 TokenA balance: ", await tokenA.balanceOf(user1.address));
    console.log("user1 TokenB balance: ", await tokenB.balanceOf(user1.address));
    console.log("user2 TokenA balance: ", await tokenA.balanceOf(user2.address));
    console.log("user2 TokenB balance: ", await tokenB.balanceOf(user2.address));
    console.log("user3 TokenA balance: ", await tokenA.balanceOf(user3.address));
    console.log("user3 TokenB balance: ", await tokenB.balanceOf(user3.address));
    
    // === ВНОСИМ ЛИКВИДНОСТЬ ===
    
    tx = await tokenA.connect(user1).transfer(pair.address, amountA);
    await tx.wait();
    tx = await tokenB.connect(user1).transfer(pair.address, amountB);
    await tx.wait();
    tx = await pair.connect(user1).mint(user1.address);
    await tx.wait();

    tx = await tokenA.connect(user2).transfer(pair.address, amountA);
    await tx.wait();
    tx = await tokenB.connect(user2).transfer(pair.address, amountB);
    await tx.wait();
    tx = await pair.connect(user2).mint(user2.address);
    await tx.wait();

    console.log(" === BALANCES + LIQUIDITY === ");
    console.log("user1 TokenA balance: ", await tokenA.balanceOf(user1.address));
    console.log("user1 TokenB balance: ", await tokenB.balanceOf(user1.address));
    console.log("user1 LP balance: ", await pair.balanceOf(user1.address));
    console.log("user2 TokenA balance: ", await tokenA.balanceOf(user2.address));
    console.log("user2 TokenB balance: ", await tokenB.balanceOf(user2.address));
    console.log("user2 LP balance: ", await pair.balanceOf(user2.address));
    console.log("ZeroAddress LP balance: ", await pair.balanceOf(ethers.constants.AddressZero));

    // === ДЕЛАЕМ SWAP ===

    const CallUni = await ethers.getContractFactory("CallUni");
    let callUni = await CallUni.deploy();
    await callUni.deployed();

    const amountBin = 1003;
    const amountAout = 100;

    tx = await tokenB.connect(user3).transfer(pair.address, amountBin);
    await tx.wait();
    tx = await callUni.call(pair.address, amountAout, 0, user3.address, "0x00");
    await tx.wait();

    console.log(" === BALANCES AFTER SWAP === ");
    console.log("user3 TokenA balance: ", await tokenA.balanceOf(user3.address));
    console.log("user3 TokenB balance: ", await tokenB.balanceOf(user3.address));
    console.log("user3 LP balance: ", await pair.balanceOf(user3.address));

    // === ВЫВОД ЛИКВИДНОСТИ ===

    const lpToken = await pair.balanceOf(user2.address);
    tx = await pair.connect(user2).transfer(pair.address, lpToken.div(2));
    await tx.wait();
    tx = await pair.connect(user2).burn( user2.address);
    await tx.wait();

    console.log(" === BALANCES + LIQUIDITY AFTER BURN === ");
    console.log("user1 TokenA balance: ", await tokenA.balanceOf(user1.address));
    console.log("user1 TokenB balance: ", await tokenB.balanceOf(user1.address));
    console.log("user1 LP balance: ", await pair.balanceOf(user1.address));
    console.log("user2 TokenA balance: ", await tokenA.balanceOf(user2.address));
    console.log("user2 TokenB balance: ", await tokenB.balanceOf(user2.address));
    console.log("user2 LP balance: ", await pair.balanceOf(user2.address));
    console.log("ZeroAddress LP balance: ", await pair.balanceOf(ethers.constants.AddressZero));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
