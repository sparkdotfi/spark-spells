// Throwaway CLI for this draft PR only. It is copied into a checkout of
// marsfoundation/spell-caster (src/bin/castSpell.ts) at CI time and reuses its
// modules, so nothing upstream is modified.
//
// Why: spell-caster executes foreign-domain spells through a SUBMISSION_ROLE
// based executor (executeForeignDomainSpell). The Gnosis executor is still the
// legacy AMB bridge executor and has no SUBMISSION_ROLE(), so that path reverts.
// Here Gnosis is executed the same way the forge test harness does it
// (SpellRunner._executeForeignPayloads): impersonate the executor and call
// executeDelegateCall(spell, execute()).
import assert from 'node:assert'
import { writeFileSync } from 'node:fs'
import { parseArgs } from 'node:util'
import { executeForeignDomainSpell, executeMainnetSpell } from '@sparkdotfi/common-contracts/spell'
import { TenderlyTestnetFactory, getRandomChainId } from '@sparkdotfi/common-testnets'
import { HttpClient } from '@sparkdotfi/common-universal/http-client'
import { Logger } from '@sparkdotfi/common-universal/logger'
import { type Address, encodeFunctionData, parseEther } from 'viem'
import { gnosis } from 'viem/chains'
import { Config, getConfig } from '../config'
import { IEnv } from '../config/environment/IEnv'
import { ForkAndExecuteSpellReturn } from '../forkAndExecuteSpell'
import { deployContract } from '../periphery/forge'
import { buildAppUrl } from '../periphery/spark-app'
import { ensureAbsolutePath } from '../utils/fs'
import { getChainIdFromSpellName } from '../utils/getChainIdFromSpellName'

// Chains whose executor is the legacy AMB bridge executor (no SUBMISSION_ROLE).
const LEGACY_EXECUTOR_CHAIN_IDS: number[] = [gnosis.id]
// Well below Gnosis' ~17M block gas limit, far above what a payload needs.
const LEGACY_EXECUTE_GAS = 10_000_000n

const legacyExecutorAbi = [
  {
    type: 'function',
    name: 'executeDelegateCall',
    stateMutability: 'payable',
    inputs: [
      { name: 'target', type: 'address' },
      { name: 'data', type: 'bytes' },
    ],
    outputs: [
      { name: '', type: 'bool' },
      { name: '', type: 'bytes' },
    ],
  },
] as const

const spellAbi = [
  { type: 'function', name: 'execute', stateMutability: 'nonpayable', inputs: [], outputs: [] },
] as const

// getConfig() insists on a github token even for CLI use; map it onto GITHUB_TOKEN.
class ProcessEnv implements IEnv {
  string(key: string, fallback?: string): string {
    const value = this.optionalString(key) ?? fallback
    assert(value, `Missing env var: ${key}`)
    return value
  }
  optionalString(key: string): string | undefined {
    if (key === 'github-token') {
      return process.env.GITHUB_TOKEN ?? 'not-needed'
    }
    return process.env[key]
  }
}

async function forkAndExecuteSpell(spellName: string, config: Config): Promise<ForkAndExecuteSpellReturn> {
  const originChainId = getChainIdFromSpellName(spellName)
  const chainConfig = config.networks[originChainId]
  assert(chainConfig, `Chain not found for chainId: ${originChainId}`)

  const tenderlyFactory = new TenderlyTestnetFactory(
    {
      account: config.tenderly.account,
      apiKey: config.tenderly.apiKey,
      project: config.tenderly.project,
    },
    new HttpClient({}, Logger.SILENT),
  )
  const forkChainId = getRandomChainId()
  const result = await tenderlyFactory.create({
    id: `spell-caster-${chainConfig.chain.id}`,
    origin: chainConfig.name,
    forkChainId,
  })
  assert(result.publicRpcUrl)

  const spellAddress = await deployContract({
    contractName: spellName,
    rpc: result.rpcUrl,
    from: config.deployer,
    cwd: config.spellsRepoPath,
  })
  console.log(`Deployed ${spellName} to ${spellAddress} on fork ${forkChainId}`)

  if (chainConfig.name === 'mainnet') {
    await executeMainnetSpell({
      client: result.client,
      sparkProxy: chainConfig.sparkProxy,
      pauseProxy: chainConfig.pauseProxy,
      spell: spellAddress,
    })
  } else if (LEGACY_EXECUTOR_CHAIN_IDS.includes(originChainId)) {
    await executeLegacyForeignDomainSpell({
      client: result.client,
      executor: chainConfig.sparkSpellExecutor,
      spell: spellAddress,
    })
  } else {
    await executeForeignDomainSpell({
      client: result.client,
      executor: chainConfig.sparkSpellExecutor,
      account: config.deployer,
      spell: spellAddress,
    })
  }
  console.log(`Executed ${spellName}`)

  await result.cleanup()

  return {
    spellName,
    originChainId,
    forkRpc: result.publicRpcUrl,
    forkChainId,
    appUrl: buildAppUrl({ rpc: result.publicRpcUrl, originChainId }),
  }
}

// Mirrors SpellRunner._executeForeignPayloads for Gnosis: the legacy AMB bridge
// executor only lets itself call executeDelegateCall, so impersonate it on the fork.
async function executeLegacyForeignDomainSpell({
  client,
  executor,
  spell,
}: {
  client: Awaited<ReturnType<TenderlyTestnetFactory['create']>>['client']
  executor: Address
  spell: Address
}): Promise<void> {
  const spellCode = await client.getCode({ address: spell })
  assert(spellCode, 'spell code is not set')

  await client.setBalance(executor, parseEther('1'))

  const call = {
    address: executor,
    abi: legacyExecutorAbi,
    functionName: 'executeDelegateCall',
    args: [spell, encodeFunctionData({ abi: spellAbi, functionName: 'execute' })],
    account: executor,
    // The legacy executor swallows the inner delegatecall's failure and returns (false, data)
    // instead of reverting. Gas estimation therefore settles on the smallest gas at which the
    // OUTER call succeeds, i.e. one where execute() runs out of gas and silently does nothing
    // (verified on an anvil fork: ~41k gas, 0 logs vs ~242k gas, 12 logs with explicit gas).
    // So pin the gas and check the returned success flag explicitly.
    gas: LEGACY_EXECUTE_GAS,
  } as const

  const { result } = await client.simulateContract(call)
  const [success, returnData] = result
  assert(success, `${spell} execute() reverted inside executeDelegateCall, return data: ${returnData}`)

  await client.assertWriteContract(call)
}

async function main(): Promise<void> {
  const args = parseArgs({
    options: {
      root: { type: 'string' },
      out: { type: 'string' },
    },
    allowPositionals: true,
    strict: true,
  })
  const rootPath = args.values.root
  const spellNames = args.positionals

  assert(rootPath, 'Pass --root /path/to/spark-spells')
  assert(spellNames.length > 0, 'Pass at least one spell name, ex. SparkEthereum_20260910')

  const config = getConfig(new ProcessEnv(), ensureAbsolutePath(rootPath))

  const results: ForkAndExecuteSpellReturn[] = []
  const failures: { spellName: string; error: string }[] = []

  // Run sequentially so one failing spell does not hide the others' results.
  for (const spellName of spellNames) {
    try {
      console.log(`\n=== ${spellName} ===`)
      const result = await forkAndExecuteSpell(spellName, config)
      console.log(`Fork RPC: ${result.forkRpc}`)
      console.log(`App URL:  ${result.appUrl}`)
      results.push(result)
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      console.error(`FAILED ${spellName}: ${message}`)
      failures.push({ spellName, error: message })
    }
  }

  if (args.values.out) {
    writeFileSync(args.values.out, JSON.stringify({ results, failures }, null, 2))
  }

  if (failures.length > 0) {
    process.exitCode = 1
  }
}

await main()
