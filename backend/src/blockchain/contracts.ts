import { ethers } from "ethers";
import { createRequire } from "module";
import { type ChainKey, requireAddress } from "../config/env.js";
import { getProvider } from "./providers.js";
import { getSigner } from "./wallet.js";

const require = createRequire(import.meta.url);
const { abi: LendingPoolABI } = require("../abis/LendingPoolContract.json") as { abi: ethers.InterfaceAbi };
const ERC20ABI = require("../abis/ERC20.json") as ethers.InterfaceAbi;

/**
 * Returns a read-only LendingPool contract instance connected to a JsonRpcProvider.
 * Use for view/static calls — no gas, no signing.
 */
export function getLendingPoolRead(chain: ChainKey): ethers.Contract {
  return new ethers.Contract(
    requireAddress(chain, "lendingPool"),
    LendingPoolABI,
    getProvider(chain)
  );
}

/**
 * Returns a signing LendingPool contract instance.
 * Use for state-changing calls that require a transaction.
 */
export function getLendingPoolWrite(chain: ChainKey): ethers.Contract {
  return new ethers.Contract(
    requireAddress(chain, "lendingPool"),
    LendingPoolABI,
    getSigner(chain)
  );
}

/**
 * Returns a signing ERC20 contract instance for any token address.
 */
export function getERC20Write(tokenAddress: string, chain: ChainKey): ethers.Contract {
  return new ethers.Contract(tokenAddress, ERC20ABI, getSigner(chain));
}

/**
 * Returns a read-only ERC20 contract instance for any token address.
 */
export function getERC20Read(tokenAddress: string, chain: ChainKey): ethers.Contract {
  return new ethers.Contract(tokenAddress, ERC20ABI, getProvider(chain));
}
