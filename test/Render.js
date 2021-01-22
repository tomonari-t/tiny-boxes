const { expect } = require("chai");

describe("TinyBoxes Rendering", function() {
    let tinyboxes;
    let owner;
    let addr1;
    let addr2;
    let addrs;

     // `beforeEach` will run before each test, re-deploying the contract every
    // time. It receives a callback, which can be async.
    beforeEach(async function () {
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        // deploy the Animation lib
        const Animation = await hre.ethers.getContractFactory("Animation",{
            libraries: {
                FixidityLib: "0x34cFa7d44a6698E68FB067e3C48ebB831873E534",
                Utils: "0xA87158c03e304d88C93D2a9B8AE2046e8EaB29b9"
            }
        });
        const animation = await Animation.deploy();

        await animation.deployed();

        console.log("Animation deployed to:", animation.address);

        // deploy the Renderer lib
        const TinyBoxesRenderer = await hre.ethers.getContractFactory("TinyBoxesRenderer",{
            libraries: {
                Colors: "0x0B37DC0Adc2948f3689dfB8200F3419424360d85",
                Utils: "0xA87158c03e304d88C93D2a9B8AE2046e8EaB29b9"
            }
        });
        const tinyboxesrenderer = await TinyBoxesRenderer.deploy(animation.address);

        await tinyboxesrenderer.deployed();

        console.log("TinyBoxesRenderer deployed to:", tinyboxesrenderer.address);

        // deploy random stub
        const RandomStub = await hre.ethers.getContractFactory("RandomStub");
        const randomstub = await RandomStub.deploy();

        await randomstub.deployed();

        console.log("RandomStub deployed to:", randomstub.address);

        // deploy the main contract
        const TinyBoxes = await hre.ethers.getContractFactory("TinyBoxes");
        tinyboxes = await TinyBoxes.deploy(randomstub.address, tinyboxesrenderer.address);

        await tinyboxes.deployed();

        console.log("TinyBoxes deployed to:", tinyboxes.address);
    });

    it("Can Unpause", async function() {
        await tinyboxes.setPause(false);
        expect(await tinyboxes.paused()).to.equal(false);
    });

    it("Can Mint Promo", async function() {
        await tinyboxes.mintPromo(addr1.address);
        expect(await tinyboxes.balanceOf(addr1.address)).to.equal(1);
    });

    it("Method tokenPreview should return a SVG string", async function() {
        const art = await tinyboxes.tokenPreview(1111, [100,50,70], [30,5], [100,100,100,100], [50,50], 63, [50,10,1], [0,10,7,70], '');
        expect(art).to.be.a('string');
    });
});