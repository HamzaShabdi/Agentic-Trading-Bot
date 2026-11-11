# Aeonix

**A context-aware, precision-timed M5 trading Expert Advisor for MetaTrader 5.**

Aeonix is an experimental MQL5 Expert Advisor created for the **AgentX hackathon**. It starts with an MA 5 / MA 20 crossover, but does not treat the crossover as a complete trade decision. A directional cross is accepted only when MA 200 is on the corresponding side of both averages. The EA then stages market analysis, candle-pattern and wick checks, a final direction decision, and risk controls around that signal.

> Aeonix is a deterministic, rule-based trading system. “Aegis” and “Phoenix” are names for software decision modules, not trained AI models. Trading involves substantial risk; no profitability or accuracy is guaranteed.

## Why Aeonix is different from a basic SMA EA

A basic SMA crossover EA can enter as soon as its averages cross. Aeonix uses the cross as a **setup trigger**, then evaluates more context before deciding whether and which way to trade:

- **Aegis** assesses market regime, direction, strength, volatility, behavior, bias, and trade-management mode.
- **Phoenix / HAFS** evaluates a named candle-pattern case and the wick support of the live signal candle and two preceding candles.
- **Staged calculation** caches context at 290 seconds, then performs final checks and freezes the direction at 298 seconds into the M5 signal candle.
- **Immediate execution** attempts the order on the first available tick at or after the 298-second decision. It does not intentionally wait for the next candle or 301 seconds.
- **Explicit stop-loss line**: the entry request includes calculated broker-side SL and TP prices. Aegis-mode trailing can subsequently move the SL in a protective direction.

The design is intended to make a crossover decision more contextual and explainable. Actual accuracy or performance improvements must be established through reproducible testing; they are not assumed here.

## System at a glance

| Layer | Responsibility |
|---|---|
| Signal | Detect an MA 5 / MA 20 crossover while the M5 candle is forming; require MA 200 below both for BUY or above both for SELL. |
| Aegis | Classify market context, estimate trend or reversal bias, assess the trade type, and select a protection mode. |
| Phoenix / HAFS | Route the setup into a candle case, evaluate A/B/C wick support, and pass a direction to Aegis final-decision logic. |
| Execution | Freeze BUY or SELL at the final calculation stage and submit an order with calculated SL/TP. |
| Management | Check stop-loss conditions, apply mode-based trailing, and evaluate basket and time-based exits. |

## Aegis: market context and trade management

Aegis is the context and risk-management layer. It uses several inputs rather than relying solely on the crossover:

- **Market type:** the current source classifies conditions as trending or ranging using MA 5, MA 20, and MA 200 alignment. Although a breakout enum exists, the reviewed classification function does not currently return a breakout state.
- **Trend direction:** buy, sell, or none, based on the coded MA conditions.
- **Trend strength:** weak, normal, or strong, using MA 5 / MA 20 separation.
- **Volatility:** low, normal, high, or extreme, based on recent M5 candle ranges. The current thresholds mark range expansion of 1.7x as high and 2.5x as extreme versus the average of prior ranges.
- **Market behavior:** normal, choppy, momentum, rejection, or unstable.
- **Decision and bias:** allow, caution, or reject; and trend, reversal, or unknown. These help classify the setup and preferred trade type.
- **Profit-management mode:** Tight, Normal, or Runner. Strong trend conditions, some strong reversal conditions, and cautionary market states influence the selected mode.

The exact rules are those implemented in the EA source; this is not a forecast or a guarantee that a market classification will be correct.

## Phoenix / HAFS: pattern and wick reasoning

Phoenix is the name used in the code for the case-specific “mastermind” decision branches. HAFS provides the candle-pattern and wick inputs those branches evaluate.

### Three-candle context

- **A** is the live signal candle.
- **B** is the immediately preceding candle.
- **C** is the candle before B.

The EA defines **12 base case labels** (BUY 1–6 and SELL 1–6) and **4 reversal variants** (BUY 1 / 4 reversal and SELL 1 / 4 reversal). Case assignment uses bullish and bearish candle-body states across A, B, and C; case-specific logic then evaluates wick support.

### Wick and candle-strength checks

- A lower-wick-dominant signal can support BUY; an upper-wick-dominant signal can support SELL, subject to the configured wick-difference threshold.
- B and C contribute their own buy/sell wick-support flags.
- The final case logic combines the A/B/C flags and may resolve in the crossover direction or in the opposite direction.
- Minimum total wick size and minimum candle-strength thresholds can reject a setup.
- Source defaults include a 10% wick-difference threshold, a 40% strong-wick threshold, and minimum wick size of 1.0 price unit. These are configurable inputs/values, not universal market standards.

After the case-specific direction is produced, Aegis maps it to a trend or reversal trade type and applies the cached context and preferred-trade logic. The resulting direction is frozen before order submission.

## The 290s → 298s execution window

The signal candle is an M5 candle: 300 seconds in duration. Aeonix uses its final seconds for a staged decision rather than waiting until a later candle.

| Candle age | Stage | Work performed |
|---:|---|---|
| Cross detected | Capture setup | Record crossover direction and signal-candle time; save preceding-candle data. |
| **290 seconds** | Pre-processing | Cache market type, trend direction and strength, volatility, behavior, Aegis decision, market bias, candle strength, and eligible B/C wick/case data. |
| **298 seconds or later** | Final calculation | On the first available tick at or after 298.000 seconds, recheck candle strength, calculate the live A-candle wick, detect the final HAFS case, and freeze BUY or SELL. |
| Same eligible tick | Execution attempt | If the final direction is valid and a quote is available, immediately submit the BUY/SELL request with calculated SL and TP. |

This is **tick-driven**, not a timer that guarantees a quote at exactly 298.000 seconds. If no tick arrives at that instant, processing occurs on a later available tick. The intended flow does not wait for 301 seconds or for the next M5 bar.

## Stop-loss line and adaptive trailing

Aeonix's current protection emphasis is a real broker-side SL attached to the entry, plus mode-based trailing—not a claim that the legacy stepped SmartProfitLock ladder is the active protection mechanism.

### Entry SL/TP

- The BUY/SELL request supplies calculated **SL and TP price levels** to the broker.
- The default `TradeSLMoney` input is **$2.00**; the EA converts that money amount into a price distance using symbol tick values, tick size, and volume.
- The default `BasketTP` is **$3.00**. Broker minimum stop/freeze distances can require a wider price distance. Fees, slippage, execution, and symbol rules mean actual loss/profit can differ from a configured amount.
- If an entry-based SL cannot initially be placed within broker limits, the EA also includes per-tick SL retry logic.

### Aegis-mode trailing SL

The mode-based trailing stop updates the broker's position SL and does not loosen an existing stop:

| Mode | Trailing activation | Intended trailing distance |
|---|---:|---:|
| **Runner** | $0.20 open position profit | 0.50 price units |
| **Normal** | $0.15 open position profit | 0.35 price units |
| **Tight** | $0.15 open position profit | 0.25 price units |

**Runner clarification:** $0.20 is the open-profit activation threshold that starts trailing. It is not a promise that the stop locks exactly $0.20 of profit. The 0.50 figure is a price distance, not a dollar amount. Broker stop/freeze rules may widen the effective distance.

### Profit confirmation and reversal grace

The current version adds a short grace after a mode's trailing activation:

1. As soon as position profit reaches its mode's activation threshold, the broker-side trailing SL is recalculated on every tick, subject to broker stop/freeze restrictions.
2. The EA starts a **45-second grace** after profit reaches **twice** the mode's activation threshold on **two consecutive ticks**: Runner at $0.40; Normal and Tight at $0.30.
3. During grace, the EA tracks the favorable-price peak and intended trailing level on every tick, while moving the broker-side SL to the configured **-$0.40 monetary loss level** so the regular tight trail does not close the trade on an ordinary pullback.
4. If position profit reaches **-$0.40 during grace**, the EA attempts to close the position. This is not a guaranteed fill price: fast moves, gaps, spread, or broker stop/freeze restrictions can cause an earlier or larger loss. The EA logs when the broker prevents the grace SL update.
5. After 45 seconds, the EA restores the trailing level derived from the best favorable price observed during grace. If that level has already been crossed, it attempts to close immediately; otherwise, normal per-tick mode trailing continues.

Once this grace has started, the legacy recovery-timer / drawdown-recovery exits are suppressed for the basket so they do not preempt the grace loss cap or the post-grace trailing exit. The existing **300-second maximum-hold exit** and configured basket / monetary stop targets remain enabled and can still close a position independently.

### Other coded protections and exits

Reviewed source defaults and checks include:

- `LotSize`: 0.01.
- `BasketTP`: $3.00.
- `BasketSL`: $2.00, subject to the source's hold-time and symbol-specific conditions.
- `EmergencySL`: $3.00 after a 60-second minimum trade age for applicable symbols.
- `TradeSLMoney`: $2.00 per-position monetary stop target.
- A five-minute (300-second) maximum-hold exit for an open position.
- A 45-second trailing-activation grace with a -$0.40 software loss limit.
- Recovery-related state and exit handling.

These are configurable/source defaults, not recommended account settings. The EA has symbol-specific branches; users should check the current source and test on their broker and instrument.

## How Aeonix differs from the earlier SmartProfitLock version

The Round 1 README described profit-lock logic. The current Aeonix source shifts the protection story toward **visible broker-side SL levels and Aegis-mode trailing**, while adding the staged market-analysis and execution pipeline.

| Earlier project framing | Current Aeonix source |
|---|---|
| SmartProfitLock-centered profit management | Calculated SL/TP prices are supplied with the entry request. |
| Less emphasis on an explicit chart/broker SL | Entry SL is a broker-side price level; fixed-money SL retry and Aegis trailing are also coded. |
| Crossover plus profit-management focus | Crossover is followed by Aegis context, Phoenix/HAFS cases, and wick/candle-strength checks. |
| No documented late-candle staged execution in the Round 1 README | 290s pre-processing → 298s final calculation → immediate same-tick execution attempt. |

The previous SmartProfitLock source was not included in the files reviewed for this README, so this is a comparison with the earlier project description, not a line-by-line code diff. In the current snapshot, the legacy stepped SmartProfitLock ladder block is commented out; its name and some state variables remain. The active per-tick trailing function is `ManageModeTrailingSL()`.

## Configuration and technology

- **Platform:** MetaTrader 5
- **Language:** MQL5
- **Main source:** `Aeonix.mq5`
- **Timeframe used by the strategy:** M5
- **Trade API:** MQL5 `CTrade`
- **Main moving averages:** MA 5, MA 20, and MA 200 (MA 200 is used by market-context logic)

The EA exposes configurable values for lot size, wick thresholds, candle-strength threshold, money stop, basket targets, and session filtering. Check the source inputs before running it; defaults are not risk recommendations.

## Testing and validation

Before any live use:

1. Compile the exact submitted `.mq5` source in MetaEditor.
2. Backtest multiple instruments and market regimes with realistic spread, commission, slippage, and broker stop constraints.
3. Use out-of-sample data; record the exact EA version, parameters, symbol, timeframe, and dates.
4. Demo-forward-test the 290s/298s timing, order-request timestamps, rejected setups, SL placement/retries, trailing modifications, and exits.
5. Measure results such as drawdown, expectancy, win/loss distribution, and trigger-to-order latency. Do not equate a working order pipeline with trading accuracy or profitability.
6. Never treat a short backtest or demo run as evidence of future returns.

No verified win rate, accuracy improvement, or profitability result is claimed in this repository.

## Hackathon value

Aeonix demonstrates a modular approach to automated trade decisions:

**Aegis reads market context → Phoenix/HAFS evaluates candle cases → direction is frozen → execution and SL/TP management take over.**

The differentiator is not simply “MA 5 crosses MA 20.” The cross is direction-filtered by MA 200 and followed by an explainable, staged pipeline: regime and bias analysis, candle strength, pattern and wick evidence, potential direction reversal, a 290/298-second decision window, and immediate execution on the eligible tick.

## Disclaimer

Aeonix is an experimental software project for education and testing, not financial advice. Trading financial instruments can result in substantial or total loss. Stops do not guarantee a precise exit price during gaps, slippage, or fast markets. Test in MetaTrader 5's Strategy Tester and on a demo account, and understand the risks before considering live trading.

## License

No license is specified. Add a `LICENSE` file only after choosing the terms under which others may use, modify, and distribute the project.
