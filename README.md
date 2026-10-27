# Aeonix --- Intelligent Market-Analysis Trading EA

Aeonix is an experimental MetaTrader 5 Expert Advisor (EA) built around
staged market analysis, candle-strength evaluation, wick-pattern logic,
and mode-based trade management. Instead of relying only on a simple
moving-average crossover to trigger an immediate trade, the design
evaluates market context and applies additional decision and
risk-management layers.

> **Important:** Verify the current `.mq5` source before publishing
> performance claims or exact timing values. The source reviewed for
> this README contains a 180-second hold-time check, so this README
> avoids claiming a 250--260 second hold time.

## Project Overview

Aeonix combines several layers of analysis and trade management:

-   **AEGIS** --- market-context analysis and decision support.
-   **Phoenix / HAFS** --- candle and wick-pattern evaluation.
-   **Market classification** --- trend, range, breakout, volatility,
    and behavior states.
-   **Adaptive risk modes** --- Runner, Normal, and Tight.
-   **Smart profit protection** --- mode-aware profit-locking and
    recovery handling.

The EA is intended for research, development, and testing in MetaTrader
5. It does not guarantee profitable results.

## What Makes Aeonix Different?

A conventional crossover strategy may enter as soon as a moving-average
condition is met. Aeonix adds contextual analysis before a trade
decision, then applies trade-management rules after entry.

### 1. Staged Candle Analysis

The source reviewed includes a preprocessing condition around **290
seconds after candle open**. At that point, it caches values such as:

-   Market type
-   Trend direction and strength
-   Volatility state
-   Market behavior
-   AEGIS decision and market bias
-   Candle-strength information
-   HAFS preprocessing data

Timing depends on the current source implementation and timeframe.
Confirm the timing logic before describing it as a fixed product
guarantee.

### 2. AEGIS --- Market Intelligence

AEGIS is the market-analysis and decision-support layer. The reviewed
source includes logic for evaluating:

-   Trending, ranging, and breakout conditions
-   Trend direction and strength
-   Volatility states
-   Normal, choppy, momentum, rejection, and unstable behavior
-   Cached market context used by later decision logic

The goal is to use more than a single indicator signal when evaluating a
potential setup.

### 3. Phoenix / HAFS --- Candle and Wick Logic

Phoenix / HAFS adds candle-pattern and wick-based evaluation. The
reviewed source includes HAFS buy/sell case families, wick confirmation,
and cached candle data.

These checks are intended to help evaluate the shape and context of
price movement before a trade is taken. Their effectiveness must be
validated through testing.

## Risk and Trade Management

### Runner, Normal, and Tight Modes

Aeonix includes three named profit/risk-management modes:

-   **Runner** --- designed to manage trades with room for a larger
    favorable move.
-   **Normal** --- the standard management mode.
-   **Tight** --- designed for more conservative or tightly managed
    conditions.

Market-condition logic can influence the selected mode. Review the
current source to confirm the precise entry conditions and parameters
for each mode before documenting them as fixed specifications.

### Smart Profit Lock

The source includes smart profit-lock logic and a `GetAegisProfitMode`
function. Profit protection behavior can vary according to the active
management mode.

### Grace Timer and Recovery Logic

The source includes recovery-related state and a **30-second recovery
timer**. The recovery logic uses a configured profit threshold
(`RecoveryLock`) when evaluating whether a trade should remain open or
be closed.

Confirm the exact current behavior and threshold values in the latest
source before publishing detailed claims about trade exits.

### Targets and Protective Limits

The reviewed source contains these default input values:

  Setting           Default value in reviewed source
  --------------- ----------------------------------
  `BasketTP`                                   `3.0`
  `BasketSL`                                   `2.0`
  `EmergencySL`                                `3.0`

These are source defaults, not guaranteed outcomes. Actual behavior can
depend on broker execution, symbol specifications, configuration, and
other EA logic.

The reviewed source also contains a **180-second hold-time check**. Do
not describe the hold time as 250--260 seconds unless the latest `.mq5`
file confirms that value.

## High-Level Workflow

1.  Collect and evaluate recent market data.
2.  Classify market conditions, trend, volatility, and behavior.
3.  Cache relevant context during the preprocessing stage.
4.  Apply AEGIS market analysis and Phoenix / HAFS candle and wick
    checks.
5.  Evaluate whether a trade setup meets the EA's conditions.
6.  Manage an open trade using the applicable risk mode and
    profit-protection logic.

This is a high-level description. Exact execution order and conditions
should be confirmed against the source version submitted with the
project.

## Technology Stack

-   **Platform:** MetaTrader 5
-   **Language:** MQL5
-   **Artifact:** Expert Advisor (`.mq5`)

## Testing and Validation

Before using Aeonix on a live account:

-   Compile the submitted source in MetaEditor and resolve all warnings
    or errors.
-   Run Strategy Tester backtests across different market conditions.
-   Use out-of-sample periods to reduce the risk of overfitting.
-   Test realistic spreads, commissions, slippage, and broker
    stop-distance restrictions.
-   Run demo-forward tests and inspect order execution, exits, and
    recovery behavior.
-   Record test dates, symbols, timeframes, settings, and results.
-   Avoid presenting a backtest or a short demo run as proof of future
    profitability.

## Repository Checklist

Before making the repository public:

-   [ ] Ensure the repository name, README, and EA identity match.
-   [ ] Confirm the `.mq5` header and internal program name use the
    intended Aeonix name.
-   [ ] Verify timing, hold-time, and recovery claims against the exact
    submitted source.
-   [ ] Remove account numbers, credentials, private paths, and other
    sensitive information.
-   [ ] Include a license only if you have chosen the terms under which
    others may use the code.
-   [ ] Add screenshots or test reports only when they are genuine and
    accurately labeled.

## Hackathon Value Proposition

Aeonix explores a layered trading-EA architecture that combines market
classification, cached context, candle and wick evaluation, and
mode-based trade management. The project can be evaluated on the clarity
of its architecture, reproducibility of its tests, and the quality of
its risk controls---not on unsupported claims of guaranteed returns.

## Disclaimer

Aeonix is provided for educational and experimental purposes. Trading
financial instruments, including gold and other CFDs, involves
substantial risk. This repository is not financial advice, and no
strategy or EA can guarantee profits. Test thoroughly on a demo
environment and understand the risks before considering live use.

## License

No license is specified here. Add a `LICENSE` file if you want to define
how others may use, modify, and distribute this repository.
