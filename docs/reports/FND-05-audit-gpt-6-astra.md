# [GPT-6-Astra] Audit — PR 92 (FND-05) — security, quality

## Verdict

**PASS WITH FINDINGS** — F-1 through F-4 are closed. Only F-5 remains: the previously deferred, non-blocking documentation note. No new findings.

Reviewed `1ab55b8ebc7782f216655cd9275c041c9f9e72ef`, fix `e5a21e8`, and the implementer’s “Fix loop 2” report.

## Findings

Severity for closed findings is their original severity.

| # | Severity | Final status | Location | Evidence / conclusion | Remaining action |
|---|---|---|---|---|---|
| F-1 | **major** | **Closed** | [starknet.ts:169](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-92/client/app/src/account/starknet.ts:169) | Configuration is copied into primitive values and frozen. Validation, RPC provider, signer, deployment and funding use that same snapshot. The earlier public-to-loopback mutation now refuses before any request. Mutation during validation leaves the original endpoint, credentials and class in use. Refusal tests directly assert no `Account.execute` or signer calls. | None. |
| F-2 | **major** | **Closed** | [burner.ts:125](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-92/client/app/src/account/burner.ts:125) | Session-generation and queued-execution protections are unchanged. Burner tests pass, including cancellation during deployment checks/funding, shared preparation after sign-out, and rejection of queued old-session execution. | None. |
| F-3 | **major** | **Closed** | [burner.ts:112](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-92/client/app/src/account/burner.ts:112) | Restoration and its tests are unchanged: each new session revalidates deployment, preserves the key, migrates v1 records and binds the rederived address to network/class. Reset and binding tests pass. The node-restart integration test remains intact. | None. |
| F-4 | **minor** | **Closed** | [vendor.test.ts:78](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-92/client/app/src/account/vendor.test.ts:78) | Traversal now follows type-parameter constraints/defaults, signature parameters, exported declarations’ generic parameters and alias arguments. Both earlier reproductions and all seven new negative fixtures are detected. The clean generic fixture produces no findings. Compiler diagnostics remain enforced. | None. |
| F-5 | **note** | **Deferred; non-blocking** | [interface.cairo:91](/home/claude/projects/grimworld/.claude/worktrees/cli-AUD-92/contracts/logic/src/interface.cairo:91) | The inherited comment still says `poseidon(word, index)` rather than `poseidon(word, domain, index)`. This remains assigned to ENG-01b. | Correct the comment in the owning task. |

## Coverage

**Configuration safety.** The funder no longer rereads the caller’s configuration after construction. Its captured `fetch` is shared by validation and provider traffic. The signer is still constructed only after the local-node checks pass. Ordinary public endpoints, public nodes behind loopback tunnels, mismatched credentials and mainnet remain refused.

The tests spy directly on `Account.execute` and all four listed signer methods on every tested refusal path. The pending-check mutation test verifies the actual executing account’s address and signer public key, while stopping execution before signing. The corrected comment and report now attribute protection to the enforced endpoint boundary, without claiming published keys cannot hold value.

`createStarknetChain` also snapshots its URL and class. An independent offline probe confirmed that mutating the original configuration changes neither its provider endpoint, binding nor derived address.

**Vendor boundary.** Using the current checker helpers in memory, all **15 negative fixtures** were detected, including the seven generic additions. The clean fixture yielded no vendor origins; the broken import yielded diagnostics. The current exported API compiled without diagnostics and yielded no vendor origins.

**Unchanged coverage.** Diffs confirm that the burner implementation, its unit tests and restart integration test are unchanged from the previous audit. All contracts and `docs/BUDGETS.md` are unchanged from the original audit. Earlier conclusions therefore stand for randomness composition/purposes, mainnet refusal, administration, provider-address mutation paths, transaction-hash isolation and the 17 Cairo gas budgets. The merge after `e5a21e8` changes only the two reported documentation files.

**Verification:**

- **36 unit tests passed offline:** 21 burner tests and 15 funder tests, using cached dependencies with filesystem caching disabled.
- Vendor fixtures and the independent chain-configuration mutation probe passed.
- `git diff --check` passed; worktree clean.
- No files written, network requests or node startup. Integration and Cairo tests were not rerun.