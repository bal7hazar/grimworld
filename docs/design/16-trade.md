# 16 — Trade

> Status: **Draft v0.1** — numbers are initial values.
> Model for the auction house: the one of classic Dofus (D-46). Its description below is
> from general knowledge and was not checked against a source in this session.

## What can change hands

| | Tradable |
|---|---|
| Gold | Yes |
| Ingredients, materials, potions | Yes |
| Equipment, identified or not | Yes |
| Boss items | Yes |
| Personalised equipment | **No**, never again |
| Quest items, skills, titles, grimoire, rank | **No** |
| Cosmetics sold by the game (auras, miniature pets) | Open, with the business model (DES-15) |

Trading happens in hubs only, and only with what is in the vault or in the pack: never
during an expedition.

## Direct trade

Two players in the same hub open a trade; each puts items and gold on their side; each
confirms; the exchange is one transaction, all or nothing.

| Rule | Why |
|---|---|
| Both sides are shown in full before confirming, and any change resets both confirmations | The classic swap scam |
| One transaction swaps everything | No half-executed trade |
| No fee | Friends and guild mates help each other freely |

## Auction house

Despite its name, there are **no bids**: sellers post at a fixed price, buyers take the
offer they want.

### Principle

| | |
|---|---|
| Where | **One market for the whole world**, reachable from the auction house of any town; split by category: equipment, ingredients, stillstone, potions |
| Selling | Put a **lot** of 1, 10 or 100 identical items (equipment: lots of 1) at a price chosen by the seller |
| **Listing fee** | 2% of the asked price, paid when posting, **never refunded** |
| Duration | 7 days. Unsold lots go back to the seller's vault |
| Who can sell | Accounts with an adventurer of rank **Tin** or above. Anyone can buy |
| Number of lots | 10 per account, plus 1 per guild rank of its highest adventurer |
| Buying | For each item and each lot size, the house shows the **cheapest** lot. The buyer pays, the lot goes to their vault |
| Proceeds | Go to the seller's vault, at once, even if the seller is away |
| Shown | The average price of the item over the last sales |
| Changing a price | Withdraw and post again: the fee is paid again |

### What this does for the economy

| Effect | How |
|---|---|
| A gold sink proportional to wealth | The listing fee, paid even when nothing sells |
| A price everyone can read | Cheapest lot and average price |
| No need to be connected together | Lots wait for buyers |
| Against flooding | Limited lots per account; a fee on every posting |

### On-chain

| Point | Design |
|---|---|
| A lot | A stored record: seller, item or balance, quantity, price, expiry. Items are **escrowed** by the house when posted |
| Cheapest lot | **Not computed on-chain.** The indexer sorts; the buyer's transaction names the lot. The contract only checks that it exists, is not expired, and that the price paid is the asked price |
| Race | Two buyers for one lot: the second transaction fails cleanly and the client offers the next cheapest |
| Average price | Derived by the indexer from sale events. Display only |
| Expiry | Lazy: an expired lot cannot be bought; the seller, or anyone, can return it to the vault |
| Mode | Storage for lots and escrow, since the contract must enforce them; events for history |
| Existing code | `arcade` has an order-book package made for tokens. Our items are game entities priced in game gold: to study whether it fits or a smaller house is written ([ADR-0004](../architecture/ADR-0004-arcade-packages.md)) |

## Risks

| Risk | Answer |
|---|---|
| Gold and items sold for real money outside the game | Cannot be prevented once trade exists. Fees and lot limits slow industrial farming. Re-examined with tokenisation (Q-07) |
| Bots farming instances to sell | Every action is a paid or sponsored transaction: the paymaster policy can cap sponsored actions per account and per day |
| Price manipulation on rare items | Average over many sales, not the last one |
| Store rules | Trade in game gold between players is ordinary. Anything that turns gold or items into tokens is to be checked against store policies first ([ADR-0003](../architecture/ADR-0003-client.md)) |

## Choices made by the orchestrator (delegated by the owner, D-49)

| Choice | Reason |
|---|---|
| **One world market**, not one per town | A young on-chain game has few players. Splitting them between towns gives empty markets where nothing sells and prices mean nothing. Separate markets become interesting only with a large population; the data model keeps a `market id` on every lot so that regional markets can be opened later without migration |
| **Listing fee only, no sale tax** | One rule to understand. The fee is paid whether or not the lot sells, which already discourages overpricing and flooding |
| **Tin rank to sell** | Costs a real player one hour; costs a farm of fresh accounts one hour each |
| **Fixed lot sizes 1, 10, 100** | Makes lots comparable, so "the cheapest" means something |
