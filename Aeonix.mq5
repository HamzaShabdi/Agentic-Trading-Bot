//+------------------------------------------------------------------+
//|  MarketMakers_Simple.mq5                                         |
//|  Clean SMA Cross EA — No Martingale, No ATR                      |
//|  Safe for small accounts ($10+)                                  |
//+------------------------------------------------------------------+
#property strict
#property description "Simple SMA Cross EA — Fixed SL/TP, Trailing Stop, Session Filter"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Trade settings
input group "=== TRADE SETTINGS ==="
input double LotSize       = 0.01;   // Lot size (use 0.01 for $10 account)
input int    MagicNumber   = 55555;  // Magic number
input double RSIMomentum = 5.0;   // Minimum RSI change requires
input double WickDifferencePercent = 10.0;
input double StrongWickDifferencePercent = 40.0;   // Minimum wick difference %
enum MarketType
{
   MARKET_UNKNOWN = 0,
   MARKET_TRENDING,
   MARKET_RANGING,
   MARKET_BREAKOUT
};
MarketType CurrentMarketType = MARKET_UNKNOWN;
enum TrendDirection
{
   TREND_NONE = 0,
   TREND_BUY,
   TREND_SELL
};


enum TrendStrength
{
   STRENGTH_WEAK = 0,
   STRENGTH_NORMAL,
   STRENGTH_STRONG
};
TrendDirection CurrentTrendDirection = TREND_NONE;
TrendStrength CurrentTrendStrength = STRENGTH_WEAK;
enum VolatilityState
{
   VOL_LOW = 0,
   VOL_NORMAL,
   VOL_HIGH,
   VOL_EXTREME
};
VolatilityState CurrentVolatility = VOL_LOW;
enum AegisDecision
{
   DECISION_NONE = 0,
   DECISION_ALLOW,
   DECISION_CAUTION,
   DECISION_REJECT
};
AegisDecision CurrentDecision = DECISION_NONE;
enum MarketBehavior
{
   BEHAVIOR_NORMAL = 0,
   BEHAVIOR_CHOPPY,
   BEHAVIOR_MOMENTUM,
   BEHAVIOR_REJECTION,
   BEHAVIOR_UNSTABLE
};
MarketBehavior CurrentBehavior = BEHAVIOR_NORMAL;
enum TradeType
{
   TRADE_UNKNOWN = 0,
   TRADE_TREND,
   TRADE_REVERSAL
};
enum HAFSCase
{
   CASE_NONE = 0,

   BUY1,
   BUY2,
   BUY3,
   BUY4,
   BUY5,
   BUY6,

   SELL1,
   SELL2,
   SELL3,
   SELL4,
   SELL5,
   SELL6,

   BUY1_REV,
   BUY4_REV,

   SELL1_REV,
   SELL4_REV
};
HAFSCase CurrentHAFSCase = CASE_NONE;
enum MarketBias
{
   BIAS_UNKNOWN = 0,
   BIAS_TREND,
   BIAS_REVERSAL
};

MarketBias CurrentMarketBias = BIAS_UNKNOWN;
MarketBias CachedMarketBias = BIAS_UNKNOWN;
enum AegisProfitMode
{
   PROFIT_MODE_TIGHT = 0,
   PROFIT_MODE_NORMAL,
   PROFIT_MODE_RUNNER
};
//==================================================
// REVERSAL STRENGTH
//==================================================

enum ReversalStrength
{
   REVERSAL_WEAK = 0,
   REVERSAL_NORMAL,
   REVERSAL_STRONG
};

ReversalStrength CurrentReversalStrength = REVERSAL_WEAK;
ReversalStrength CachedReversalStrength = REVERSAL_WEAK;

//--- Profit targets (basket level in $)
input group "=== PROFIT TARGETS ==="
input double BasketTP      = 3.0;    // Close all when total profit reaches ($)
input double BasketSL      = 2.0;    // Close all when total loss reaches ($)
input double EmergencySL = 3.0;   // Hard stop, ignores hold time


input int RSIPeriod = 14;
input double BuyMomentumLevel = 55.0;
input double SellMomentumLevel = 45.0;
input double MinimumWickSize = 1.0;


//--- Session filter
input group "=== SESSION FILTER ==="
input bool   UseSessionFilter = false; // Only trade during active sessions
input int    SessionStartHour = 0;    // Start hour (server time)
input int    SessionEndHour   = 24;   // End hour (server time)

//--- Indicator handles
int MA200Handle;
int MA5Handle;
int MA20Handle;
int RSIHandle;

//--- State
bool     SignalAlreadyTraded = false;
int      BasketDirection     = 0;     // 1=BUY, -1=SELL
datetime LastBarTime         = 0;
double   PeakProfit          = 0;
bool     CrossDetected       = false; // Cross spotted during forming candle
int      CrossDirection      = 0;     // 1=buy cross, -1=sell cross
datetime TradeOpenTime = 0;
datetime LastCrossTime = 0;
bool LastTradeWasLoss = false;
ulong LastClosedDeal = 0;
datetime RecoveryLossTime = 0;
bool specialDecisionFound = false;
bool specialTradeBuy = false;
datetime TradeOpenBar = 0;
bool WaitForRecoveryCandleClose = false;
bool RecoveryWaitingForClose = false;
double SmartProfitPeak = 0.0;
double SmartProfitLock = -1.0;
bool GraceTimerActive = false;
datetime GraceStartTime = 0;
bool GraceTimerStarted = false;
bool GraceTimerFinished = false;
bool HighProfitMode = false;\
bool Trade40SecExtension = false;
datetime Trade40SecStartTime = 0;
input int ExtraTradeSeconds = 40;
bool Loss40SecExtension = false;
datetime Loss40SecStartTime = 0;
bool CrossSeenThisCandle = false;
string HAFSSignalSymbol="";
datetime CrossCandleTime = 0;
bool AegisAllowTrade = false;
bool AegisReverseTrade = false;
bool LastMA5AboveMA20 = false;
double PrevMA5 = 0;
double PrevMA20 = 0;
bool MAInitialized = false;
input bool EnableGraceTimer = true;
input int GraceTimerSeconds = 30;
bool TwoDollarDrawdownReached = false;
input double MinimumCandleStrengthPercent = 0.0;
bool PreProcessStarted = false;

MarketType CachedMarketType;
TrendDirection CachedTrendDirection;
TrendStrength CachedTrendStrength;
VolatilityState CachedVolatility;
MarketBehavior CachedBehavior;

AegisDecision CachedAegisDecision;

double CachedCandleStrength = 0.0;

bool CachedHAFSReady = false;
HAFSCase CachedHAFSCase = CASE_NONE;

bool CachedBBuyWick = false;
bool CachedBSellWick = false;

bool CachedCBuyWick = false;
bool CachedCSellWick = false;

bool CachedCaseDetected = false;
datetime LastHAFSCandle = 0;
bool HAFSCaseDetected = false;
datetime SignalCandleTime = 0;
bool FinalCalculationReady = false;
bool ExecutionArmed = false;
datetime ExecutionBarTime = 0;
double GraceProtectedProfit = 0.0;
ulong ExecutionTargetMs = 0;
long ExecutionTargetServerMs = 0;
bool CachedAWickBuy  = false;
bool CachedAWickSell = false;
double CachedAUpperWick = 0.0;
double CachedALowerWick = 0.0;
ulong SignalCandleStartMs = 0;
ulong SignalCandleStartLocalMs = 0;
int FinalDirection = 0;
bool FreezeOnlyMode = false;
bool GraceHoldingPrinted = false;
ulong ExecutionTargetLocalMs = 0;
//==================================================
// PROFIT MODE PRINT CONTROL
//==================================================

AegisProfitMode LastPrintedProfitMode = PROFIT_MODE_NORMAL;
bool ProfitModePrintInitialized = false;
//================ SPECIAL HAFS MEMORY ================
double SavedUpperWick = 0.0;
double SavedLowerWick = 0.0;

bool SavedCandleBull = false;
bool SavedCandleBear = false;

bool SavedSpecialData = false;


double SavedCUpperWick = 0;
double SavedCLowerWick = 0;

double SignalUpperWick = 0.0;
double SignalLowerWick = 0.0;

bool RecoveryTrade = false;
bool RecoveryLockActive = false;
double RecoveryLock = 0.10;
bool RecoveryMovedHigher = false;
bool RecoveryTimerStarted = false;
datetime RecoveryStartTime = 0;
double RecoveryTriggerProfit = 0.10;
int RecoveryTimerSeconds = 120;
bool RecoveryReached = false;
bool HadDeepDrawdown = false;
//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("MarketMakers Simple EA — LOADED");
   Print("Lot: ", LotSize, "  BasketTP: $", BasketTP, "  BasketSL: $", BasketSL);

   trade.SetExpertMagicNumber(MagicNumber);

   MA200Handle = iMA(_Symbol, PERIOD_M5, 200, 0, MODE_SMA, PRICE_CLOSE);
   MA5Handle   = iMA(_Symbol, PERIOD_M5, 5,   0, MODE_SMA, PRICE_CLOSE);
   MA20Handle  = iMA(_Symbol, PERIOD_M5, 20,  0, MODE_SMA, PRICE_CLOSE);
   RSIHandle   = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);

   if(MA200Handle == INVALID_HANDLE ||
      MA5Handle   == INVALID_HANDLE ||
      MA20Handle  == INVALID_HANDLE ||
      RSIHandle   == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   Print("All indicators ready");

   // Warm up indicator buffers
   double temp[];

   CopyBuffer(MA200Handle,0,0,5,temp);
   CopyBuffer(MA5Handle,0,0,5,temp);
   CopyBuffer(MA20Handle,0,0,5,temp);
   CopyBuffer(RSIHandle,0,0,5,temp);

   LastBarTime = iTime(_Symbol, PERIOD_M5, 0);

   // Check OnTimer every 10 milliseconds
   EventSetMillisecondTimer(10);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   IndicatorRelease(MA200Handle);
   IndicatorRelease(MA5Handle);
   IndicatorRelease(MA20Handle);
   IndicatorRelease(RSIHandle);
}
void OnTimer()
{
   if(!ExecutionArmed || !FinalCalculationReady)
      return;

   //==================================================
   // CURRENT TICK
   //==================================================

   MqlTick execTick;

   if(!SymbolInfoTick(_Symbol, execTick))
      return;

   long nowServerMs =
      (long)execTick.time_msc;

   long signalStartMs =
      (long)SignalCandleTime * 1000;

   long candleAgeMs =
      nowServerMs - signalStartMs;

   double candleAgeSec =
      candleAgeMs / 1000.0;

   //==================================================
   // HARD EXECUTION WINDOW
   // 300.100 SEC -> 300.300 SEC
   //==================================================

   if(candleAgeMs < 300100)
      return;

   if(candleAgeMs > 300300)
   {
      PrintFormat(
         "EXECUTION MISSED -> CANDLE AGE=%.3f SEC",
         candleAgeSec
      );

      CrossDetected         = false;
      FinalCalculationReady = false;
      ExecutionArmed        = false;

      ExecutionTargetMs       = 0;
      ExecutionTargetServerMs = 0;
      SignalCandleTime        = 0;
      FinalDirection          = 0;

      return;
   }

   //==================================================
   // ACTUAL TRADE EXECUTION
   //==================================================

   PrintFormat(
      "FINAL EXECUTION -> CANDLE AGE=%.3f SEC",
      candleAgeSec
   );

   if(FinalDirection == 1)
   {
      PrintFormat(
         "ORDER SEND -> CANDLE AGE=%.3f SEC",
         candleAgeSec
      );

      Print("EXECUTING FROZEN BUY");

      ExecuteBuyTrade();
   }
   else if(FinalDirection == -1)
   {
      PrintFormat(
         "ORDER SEND -> CANDLE AGE=%.3f SEC",
         candleAgeSec
      );

      Print("EXECUTING FROZEN SELL");

      ExecuteSellTrade();
   }
   else
   {
      Print("EXECUTION BLOCKED -> FROZEN DIRECTION UNKNOWN");

      CrossDetected         = false;
      FinalCalculationReady = false;
      ExecutionArmed        = false;

      ExecutionTargetMs       = 0;
      ExecutionTargetServerMs = 0;
      SignalCandleTime        = 0;
      FinalDirection          = 0;

      return;
   }

   //==================================================
   // RESET AFTER ORDER ATTEMPT
   //==================================================

   if(PositionSelect(_Symbol))
   {
      PrintFormat(
         "POSITION CONFIRMED -> OPEN AGE=%.3f SEC",
         candleAgeSec
      );

      CrossDetected         = false;
      FinalCalculationReady = false;
      ExecutionArmed        = false;

      ExecutionTargetMs       = 0;
      ExecutionTargetServerMs = 0;
      SignalCandleTime        = 0;
      FinalDirection          = 0;
   }
   else
   {
      Print("ORDER NOT CONFIRMED -> KEEPING EXECUTION ARMED");
   }
}
//+------------------------------------------------------------------+
//| Trend: 1=up, -1=down, 0=mixed                                   |
//+------------------------------------------------------------------+
int GetTrend()
{
   double ma200[1], ma5[1], ma20[1];
   if(CopyBuffer(MA200Handle, 0, 1, 1, ma200) < 1) return 0;
   if(CopyBuffer(MA5Handle,   0, 1, 1, ma5)   < 1) return 0;
   if(CopyBuffer(MA20Handle,  0, 1, 1, ma20)  < 1) return 0;

   if(ma5[0] > ma200[0] && ma20[0] > ma200[0]) return  1;
   if(ma5[0] < ma200[0] && ma20[0] < ma200[0]) return -1;
   return 0;
}
bool MA200TooClose()
{
   double ma200[1], ma5[1], ma20[1];

   if(CopyBuffer(MA200Handle,0,0,1,ma200) < 1) return true;
   if(CopyBuffer(MA5Handle,0,0,1,ma5) < 1) return true;
   if(CopyBuffer(MA20Handle,0,0,1,ma20) < 1) return true;

   double dist5  = MathAbs(ma5[0]  - ma200[0]);
   double dist20 = MathAbs(ma20[0] - ma200[0]);

   return (dist5 < 100 * _Point || dist20 < 100 * _Point);
}
//+------------------------------------------------------------------+
//| MA5 / MA20 cross or near-cross                                  |
//+------------------------------------------------------------------+
int DetectCross()
{
   static datetime lastPrintBar = 0;

   double ma5[2], ma20[2], ma200[1];

   if(CopyBuffer(MA5Handle,0,0,2,ma5) != 2)
      return 0;

   if(CopyBuffer(MA20Handle,0,0,2,ma20) != 2)
      return 0;

   if(CopyBuffer(MA200Handle,0,0,1,ma200) != 1)
      return 0;

   // Did MA5 and MA20 cross?
   bool crossed =
      ((ma5[1] <= ma20[1] && ma5[0] > ma20[0]) ||
       (ma5[1] >= ma20[1] && ma5[0] < ma20[0]));

   if(!crossed)
      return 0;

   datetime bar = iTime(_Symbol, PERIOD_M5, 0);

   //================ BUY =================
   if(ma200[0] < ma5[0] &&
      ma200[0] < ma20[0])
   {
      if(bar != lastPrintBar)
      {
         Print(">>> BUY CROSS EVENT <<<");
         lastPrintBar = bar;
      }

      return 1;
   }

   //================ SELL =================
   if(ma200[0] > ma5[0] &&
      ma200[0] > ma20[0])
   {
      if(bar != lastPrintBar)
      {
         Print(">>> SELL CROSS EVENT <<<");
         lastPrintBar = bar;
      }

      return -1;
   }

   return 0;
}
bool AnyCross()
{
   double ma5[1], ma20[1];

   if(CopyBuffer(MA5Handle,0,0,1,ma5) != 1)
      return false;

   if(CopyBuffer(MA20Handle,0,0,1,ma20) != 1)
      return false;

   // Returns true while the MAs are still touching/very close
   return MathAbs(ma5[0] - ma20[0]) <= 5 * _Point;
}


MarketType GetMarketType()
{
   double ma5[];
   double ma20[];
   double ma200[];

   ArraySetAsSeries(ma5, true);
   ArraySetAsSeries(ma20, true);
   ArraySetAsSeries(ma200, true);

   if(CopyBuffer(MA5Handle, 0, 0, 3, ma5) <= 0)
      return MARKET_UNKNOWN;

   if(CopyBuffer(MA20Handle, 0, 0, 3, ma20) <= 0)
      return MARKET_UNKNOWN;

   if(CopyBuffer(MA200Handle, 0, 0, 3, ma200) <= 0)
      return MARKET_UNKNOWN;

   bool bullish =
      ma5[0] > ma20[0] &&
      ma20[0] > ma200[0];

   bool bearish =
      ma5[0] < ma20[0] &&
      ma20[0] < ma200[0];

   if(bullish || bearish)
      return MARKET_TRENDING;

   return MARKET_RANGING;
}
TrendDirection GetTrendDirection()
{
   double ma5[];
   double ma20[];
   double ma200[];

   ArraySetAsSeries(ma5,true);
   ArraySetAsSeries(ma20,true);
   ArraySetAsSeries(ma200,true);

   if(CopyBuffer(MA5Handle,0,0,3,ma5) <= 0)
      return TREND_NONE;

   if(CopyBuffer(MA20Handle,0,0,3,ma20) <= 0)
      return TREND_NONE;

   if(CopyBuffer(MA200Handle,0,0,3,ma200) <= 0)
      return TREND_NONE;


   //==================================================
   // TRENDING MARKET
   // Direction comes from MA alignment
   //==================================================

   if(CurrentMarketType == MARKET_TRENDING)
   {
      if(ma5[0] > ma20[0] &&
         ma20[0] > ma200[0])
      {
         return TREND_BUY;
      }

      if(ma5[0] < ma20[0] &&
         ma20[0] < ma200[0])
      {
         return TREND_SELL;
      }

      return TREND_NONE;
   }


   //==================================================
   // RANGING MARKET
   // Direction comes from recent CLOSED candles
   //==================================================

   if(CurrentMarketType == MARKET_RANGING)
   {
      int bullCount = 0;
      int bearCount = 0;

      // Use last 3 CLOSED candles
      for(int i = 1; i <= 3; i++)
      {
         double open  = iOpen(_Symbol, PERIOD_M5, i);
         double close = iClose(_Symbol, PERIOD_M5, i);

         if(close > open)
            bullCount++;

         else if(close < open)
            bearCount++;
      }

      if(bullCount > bearCount)
         return TREND_BUY;

      if(bearCount > bullCount)
         return TREND_SELL;

      return TREND_NONE;
   }


   return TREND_NONE;
}
TrendStrength GetTrendStrength()
{
   double ma5[];
   double ma20[];

   ArraySetAsSeries(ma5,true);
   ArraySetAsSeries(ma20,true);

   if(CopyBuffer(MA5Handle,0,0,3,ma5)<=0)
      return STRENGTH_WEAK;

   if(CopyBuffer(MA20Handle,0,0,3,ma20)<=0)
      return STRENGTH_WEAK;

   double distance = MathAbs(ma5[0]-ma20[0])/_Point;

   if(distance > 80)
      return STRENGTH_STRONG;

   if(distance > 30)
      return STRENGTH_NORMAL;

   return STRENGTH_WEAK;
}
VolatilityState GetVolatilityState()
{
   double range1 = iHigh(_Symbol, PERIOD_M5, 1) - iLow(_Symbol, PERIOD_M5, 1);
   double range2 = iHigh(_Symbol, PERIOD_M5, 2) - iLow(_Symbol, PERIOD_M5, 2);
   double range3 = iHigh(_Symbol, PERIOD_M5, 3) - iLow(_Symbol, PERIOD_M5, 3);
   double range4 = iHigh(_Symbol, PERIOD_M5, 4) - iLow(_Symbol, PERIOD_M5, 4);
   double range5 = iHigh(_Symbol, PERIOD_M5, 5) - iLow(_Symbol, PERIOD_M5, 5);

   double avgRange = (range2 + range3 + range4 + range5) / 4.0;

   if(avgRange <= 0)
      return VOL_LOW;

   double expansion = range1 / avgRange;

   if(expansion >= 2.5)
      return VOL_EXTREME;

   if(expansion >= 1.7)
      return VOL_HIGH;

   if(expansion >= 0.8)
      return VOL_NORMAL;

   return VOL_LOW;
}
AegisDecision CalculateAegisDecision()
{
   MarketType market = CurrentMarketType;
   TrendDirection trend = CurrentTrendDirection;
   TrendStrength strength = CurrentTrendStrength;
   VolatilityState volatility = CurrentVolatility;
   MarketBehavior behavior = CurrentBehavior;

   //==========================
   // REJECT
   //==========================

   if(behavior == BEHAVIOR_UNSTABLE)
      return DECISION_REJECT;

   if(behavior == BEHAVIOR_CHOPPY &&
      market == MARKET_RANGING)
      return DECISION_REJECT;

   //==========================
   // CAUTION
   //==========================

   if(volatility == VOL_EXTREME)
      return DECISION_CAUTION;

   if(market == MARKET_RANGING &&
      volatility == VOL_HIGH)
      return DECISION_ALLOW;

  if(market == MARKET_TRENDING &&
   strength == STRENGTH_WEAK)
{
  
   return DECISION_ALLOW;
}

   if(behavior == BEHAVIOR_REJECTION)
   {
     
      return DECISION_ALLOW;
   }

   //==========================
   // ALLOW
   //==========================

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_STRONG &&
      behavior == BEHAVIOR_MOMENTUM)
      return DECISION_ALLOW;

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_NORMAL &&
      behavior == BEHAVIOR_NORMAL)
      return DECISION_ALLOW;
      
if(market == MARKET_TRENDING &&
   strength == STRENGTH_STRONG &&
   behavior == BEHAVIOR_NORMAL)
{
   return DECISION_ALLOW;
}
  //==========================
// RANGING + LOW VOLATILITY
//==========================

if(market == MARKET_RANGING &&
   behavior == BEHAVIOR_NORMAL &&
   volatility == VOL_LOW)
{
   return DECISION_ALLOW;
}

//==========================
// RANGING + NORMAL VOLATILITY
//==========================

if(market == MARKET_RANGING &&
   behavior == BEHAVIOR_NORMAL &&
   volatility == VOL_NORMAL)
{
   return DECISION_ALLOW;
}

   //==========================
   // DEFAULT
   //==========================

  if(market == MARKET_RANGING &&
   volatility == VOL_NORMAL &&
   behavior == BEHAVIOR_MOMENTUM)
{
   return DECISION_CAUTION;
}

return DECISION_CAUTION;
}
MarketBias GetMarketBias()
{
   MarketType market = CurrentMarketType;
   TrendStrength strength = CurrentTrendStrength;
   VolatilityState volatility = CurrentVolatility;
   MarketBehavior behavior = CurrentBehavior;

   //==========================
   // UNKNOWN
   //==========================

   if(behavior == BEHAVIOR_UNSTABLE)
      return BIAS_UNKNOWN;

   if(behavior == BEHAVIOR_CHOPPY &&
      market == MARKET_RANGING)
      return BIAS_UNKNOWN;

   if(volatility == VOL_EXTREME)
      return BIAS_UNKNOWN;

   //==========================
   // REVERSAL MARKET
   //==========================

   if(market == MARKET_RANGING &&
      volatility == VOL_HIGH)
      return BIAS_REVERSAL;

   if(behavior == BEHAVIOR_REJECTION)
      return BIAS_REVERSAL;

   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_NORMAL &&
      volatility == VOL_LOW)
      return BIAS_REVERSAL;

   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_NORMAL &&
      volatility == VOL_NORMAL)
      return BIAS_REVERSAL;

   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_MOMENTUM &&
      volatility == VOL_NORMAL)
      return BIAS_REVERSAL;
      
   if(market == MARKET_RANGING &&
     behavior == BEHAVIOR_MOMENTUM &&
     volatility == VOL_LOW)
   return BIAS_REVERSAL;
   //==========================
   // TREND MARKET
   //==========================

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_WEAK)
      return BIAS_TREND;

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_STRONG &&
      behavior == BEHAVIOR_MOMENTUM)
      return BIAS_TREND;

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_NORMAL &&
      behavior == BEHAVIOR_NORMAL)
      return BIAS_TREND;

   if(market == MARKET_TRENDING &&
      strength == STRENGTH_STRONG &&
      behavior == BEHAVIOR_NORMAL)
      return BIAS_TREND;

   //==========================
   // DEFAULT
   //==========================

   return BIAS_UNKNOWN;
}
//==================================================
// CALCULATE REVERSAL STRENGTH
// MATCHES GetMarketBias() CONDITIONS
//==================================================

ReversalStrength CalculateReversalStrength()
{
   MarketType market = CurrentMarketType;
   VolatilityState volatility = CurrentVolatility;
   MarketBehavior behavior = CurrentBehavior;

   //================================================
   // STRONG REVERSAL
   //================================================

   // Rejection behavior = strongest reversal signal
   if(behavior == BEHAVIOR_REJECTION)
   {
      return REVERSAL_STRONG;
   }

   // Ranging + High Volatility = strong reversal
   if(market == MARKET_RANGING &&
      volatility == VOL_HIGH)
   {
      return REVERSAL_STRONG;
   }


   //================================================
   // NORMAL REVERSAL
   //================================================

   // Ranging + Normal Behavior + Low Volatility
   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_NORMAL &&
      volatility == VOL_LOW)
   {
      return REVERSAL_NORMAL;
   }

   // Ranging + Normal Behavior + Normal Volatility
   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_NORMAL &&
      volatility == VOL_NORMAL)
   {
      return REVERSAL_NORMAL;
   }

   // Ranging + Momentum + Normal Volatility
   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_MOMENTUM &&
      volatility == VOL_NORMAL)
   {
      return REVERSAL_NORMAL;
   }

   // Ranging + Momentum + Low Volatility
   if(market == MARKET_RANGING &&
      behavior == BEHAVIOR_MOMENTUM &&
      volatility == VOL_LOW)
   {
      return REVERSAL_NORMAL;
   }


   //================================================
   // WEAK REVERSAL
   //================================================

   return REVERSAL_WEAK;
}
//==================================================
// CALCULATE TREND STRENGTH
// MATCHES GetMarketBias() CONDITIONS
//==================================================

TrendStrength CalculateTrendStrength()
{
   MarketType market = CurrentMarketType;
   VolatilityState volatility = CurrentVolatility;
   MarketBehavior behavior = CurrentBehavior;

   //================================================
   // WEAK TREND
   //================================================

   if(market == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_WEAK)
   {
      return STRENGTH_WEAK;
   }

   //================================================
   // STRONG TREND
   //================================================

   if(market == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_STRONG &&
      behavior == BEHAVIOR_MOMENTUM)
   {
      return STRENGTH_STRONG;
   }

   if(market == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_STRONG &&
      behavior == BEHAVIOR_NORMAL)
   {
      return STRENGTH_STRONG;
   }

   //================================================
   // NORMAL TREND
   //================================================

   if(market == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_NORMAL &&
      behavior == BEHAVIOR_NORMAL)
   {
      return STRENGTH_NORMAL;
   }

   //================================================
   // DEFAULT
   //================================================

   return STRENGTH_WEAK;
}
void PrintAegisPreferredTrade()
{
   if(CurrentMarketBias == BIAS_TREND)
   {
      if(CurrentTrendDirection == TREND_BUY)
         Print("AEGIS PREFERRED: BUY TREND");

      else if(CurrentTrendDirection == TREND_SELL)
         Print("AEGIS PREFERRED: SELL TREND");

      else
         Print("AEGIS PREFERRED: TREND UNKNOWN");
   }
   else if(CurrentMarketBias == BIAS_REVERSAL)
   {
      if(CurrentTrendDirection == TREND_BUY)
         Print("AEGIS PREFERRED: SELL REVERSAL");

      else if(CurrentTrendDirection == TREND_SELL)
         Print("AEGIS PREFERRED: BUY REVERSAL");

      else
         Print("AEGIS PREFERRED: REVERSAL UNKNOWN");
   }
   else
   {
      Print("AEGIS PREFERRED: UNKNOWN");
   }
}
MarketBehavior GetMarketBehavior()
{
   int momentum = 0;
   int rejection = 0;
   int unstable = 0;
   int choppy = 0;

   for(int i = 1; i <= 3; i++)
   {
      double open  = iOpen(_Symbol, PERIOD_M5, i);
      double close = iClose(_Symbol, PERIOD_M5, i);
      double high  = iHigh(_Symbol, PERIOD_M5, i);
      double low   = iLow(_Symbol, PERIOD_M5, i);

      double body = MathAbs(close - open);
      double range = high - low;

      if(range <= 0)
         continue;

      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;

      double bodyPercent = (body / range) * 100.0;
      double wickPercent = ((upperWick + lowerWick) / range) * 100.0;

      if(wickPercent > 70 && bodyPercent < 30)
         unstable++;

      else if(upperWick > body * 2 || lowerWick > body * 2)
         rejection++;

      else if(bodyPercent > 70)
         momentum++;

      else if(bodyPercent < 40)
         choppy++;
   }

   if(unstable >= 2)
      return BEHAVIOR_UNSTABLE;

   if(rejection >= 2)
      return BEHAVIOR_REJECTION;

   if(momentum >= 2)
      return BEHAVIOR_MOMENTUM;

   if(choppy >= 2)
      return BEHAVIOR_CHOPPY;

   return BEHAVIOR_NORMAL;
}
//+------------------------------------------------------------------+
//| RSI (previous closed bar)                                        |
//+------------------------------------------------------------------+
double GetRSI()
{
   double rsi[1];
   if(CopyBuffer(RSIHandle, 0, 0, 1, rsi) < 1) return 50;
   return rsi[0];
}

double GetRSIShift(int shift)
{
   double rsi[1];

   if(CopyBuffer(RSIHandle,0,shift,1,rsi) < 1)
      return 50;

   return rsi[0];
}

bool BuyRSI()
{
   double rsi1 = GetRSIShift(1);
   double rsi2 = GetRSIShift(2);
   double rsi3 = GetRSIShift(3);

   return (rsi1 > rsi2 && rsi2 > rsi3 && (rsi1 - rsi3) >= RSIMomentum);
}

bool SellRSI()
{
   double rsi1 = GetRSIShift(1);
   double rsi2 = GetRSIShift(2);
   double rsi3 = GetRSIShift(3);

   return (rsi1 < rsi2 && rsi2 < rsi3 && (rsi3 - rsi1) >= RSIMomentum);
}

//+------------------------------------------------------------------+
//| Candle direction (previous closed bar)                           |
//| Works on any instrument — forex, gold, synthetic indices         |
//+------------------------------------------------------------------+
bool BullishCandle()
{
   double open  = iOpen(_Symbol, PERIOD_M5, 0);
   double close = iClose(_Symbol, PERIOD_M5, 0);

   return close > open;
}

bool BearishCandle()
{
   double open  = iOpen(_Symbol, PERIOD_M5, 0);
   double close = iClose(_Symbol, PERIOD_M5, 0);

   return open > close;
}
bool OlderBullish()
{
   return iClose(_Symbol, PERIOD_M5, 1) >
          iOpen(_Symbol, PERIOD_M5, 1);
}

bool OlderBearish()
{
   return iClose(_Symbol, PERIOD_M5, 1) <
          iOpen(_Symbol, PERIOD_M5, 1);
}

bool ThirdBullish()
{
   return iClose(_Symbol, PERIOD_M5, 2) >
          iOpen(_Symbol, PERIOD_M5, 2);
}

bool ThirdBearish()
{
   return iClose(_Symbol, PERIOD_M5, 2) <
          iOpen(_Symbol, PERIOD_M5, 2);
}
bool IsDoji()
{
   return false;
}

bool OlderDoji()
{
   return false;
}

//+------------------------------------------------------------------+
//| Universal Wick Confirmation                                      |
//| finalBuy = true  -> checking BUY                                 |
//| finalBuy = false -> checking SELL                                |
//+------------------------------------------------------------------+
bool WickConfirmation(bool finalBuy)
{
   double open  = iOpen(_Symbol, PERIOD_M5, 0);
double close = iClose(_Symbol, PERIOD_M5, 0);
double high  = iHigh(_Symbol, PERIOD_M5, 0);
double low   = iLow(_Symbol, PERIOD_M5, 0);

   bool bullish = (close > open);

   double upperWick;
   double lowerWick;

   if(bullish)
   {
      upperWick = high - close;
      lowerWick = open - low;
   }
   else
   {
      upperWick = high - open;
      lowerWick = close - low;
   }
   SignalUpperWick = upperWick;
SignalLowerWick = lowerWick;

   Print("Bullish=", bullish,
         " Upper=", upperWick,
         " Lower=", lowerWick);

   double wickDiff     = MathAbs(upperWick - lowerWick);
   double totalWicks   = upperWick + lowerWick;
   double requiredDiff = totalWicks * WickDifferencePercent / 100.0;

   //======================== BUY ========================
   if(finalBuy)
   {
      if(lowerWick <= upperWick)
      {
         Print("Signal candle wick direction disagrees with BUY");
         return false;
      }

      if(wickDiff < requiredDiff)
      {
         Print("Signal candle BUY wick too weak");
         return false;
      }

      return true;
   }

   //======================== SELL ========================
   else
   {
      if(upperWick <= lowerWick)
      {
         Print("Signal candle wick direction disagrees with SELL");
         return false;
      }

      if(wickDiff < requiredDiff)
      {
         Print("Signal candle SELL wick too weak");
         return false;
      }

      return true;
   }
}


bool SpecialCandleBearish()
{
   return SavedUpperWick > SavedLowerWick;
}

bool SpecialCandleBullish()
{
   return SavedLowerWick > SavedUpperWick;
}

bool CandleBSupportsBuyWick()
{
   return (SavedLowerWick > SavedUpperWick);
}

bool CandleBSupportsSellWick()
{
   return (SavedUpperWick > SavedLowerWick);
}

bool CandleCSupportsBuyWick()
{
   return (SavedCLowerWick > SavedCUpperWick);
}

bool CandleCSupportsSellWick()
{
   return (SavedCUpperWick > SavedCLowerWick);
}

double CandleStrength(int shift)
{
   double open  = iOpen(_Symbol, PERIOD_M5, shift);
   double close = iClose(_Symbol, PERIOD_M5, shift);
   double high  = iHigh(_Symbol, PERIOD_M5, shift);
   double low   = iLow(_Symbol, PERIOD_M5, shift);

   double range = high - low;

   if(range <= 0)
      return 0;

   double body = MathAbs(close - open);

   return (body / range) * 100.0;
}

bool StrongWickDifference(double wick1, double wick2)
{
   double smaller = MathMin(wick1, wick2);

   if(smaller <= 0)
      return false;

  double diffPercent =
      (MathAbs(wick1 - wick2) / (wick1 + wick2)) * 100.0;

   Print(
   "StrongWickDifference -> Upper=", wick1,
   " Lower=", wick2,
   " Diff=", MathAbs(wick1 - wick2),
   " Total=", (wick1 + wick2),
   " Percent=", diffPercent
);

   return (diffPercent >= StrongWickDifferencePercent);
}

bool CheckMinimumWickSize()
{
   double TotalWick = SavedUpperWick + SavedLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("Trade skipped - Candle B wick too small. Total Wick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);

      return false;
   }

   return true;
}
double GetCandleStrength(int shift)
{
   double open  = iOpen(_Symbol, PERIOD_M5, shift);
   double close = iClose(_Symbol, PERIOD_M5, shift);
   double high  = iHigh(_Symbol, PERIOD_M5, shift);
   double low   = iLow(_Symbol, PERIOD_M5, shift);

   double range = high - low;

   if(range <= 0)
      return 0.0;

   double body = MathAbs(close - open);

   return (body / range) * 100.0;
}
//+------------------------------------------------------------------+
//| Checks if wick difference is strong enough for RSI decision      |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Session filter                                                   |
//+------------------------------------------------------------------+
bool InSession()
{
   if(!UseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   return (hour >= SessionStartHour && hour < SessionEndHour);
}

//+------------------------------------------------------------------+
//| Total basket floating P&L                                        |
//+------------------------------------------------------------------+
double GetBasketProfit()
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            profit += PositionGetDouble(POSITION_PROFIT);
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Close all EA positions on this symbol                            |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Reset all basket state after close                               |
//+------------------------------------------------------------------+
void ResetBasket()
{
   BasketDirection = 0;

   SignalAlreadyTraded = true;

   PeakProfit = 0;

   CrossDetected = false;

   CrossDirection = 0;

   //======== SMART PROFIT LOCK RESET ========
  SmartProfitPeak = 0.0;
SmartProfitLock = -1.0;

GraceTimerStarted  = false;
GraceTimerFinished = false;
GraceStartTime     = 0;

HighProfitMode = false;
//================ RECOVERY RESET ================

RecoveryTrade = false;
RecoveryReached = false;
RecoveryLockActive = false;
RecoveryTimerStarted = false;

RecoveryStartTime = 0;
HadDeepDrawdown = false;
Loss40SecExtension = false;
Loss40SecStartTime = 0;
TwoDollarDrawdownReached = false;
}

bool HoldTimeFinished()
{
   if(TradeOpenTime == 0)
      return true;

   return (TimeCurrent() - TradeOpenTime >= 180);
}

bool BuyCrossStillValid()
{
   double ma5[1], ma20[1];

   if(CopyBuffer(MA5Handle,0,0,1,ma5) < 1)
      return false;

   if(CopyBuffer(MA20Handle,0,0,1,ma20) < 1)
      return false;

  return (ma5[0] > ma20[0] &&
        (ma5[0] - ma20[0]) > 10 * _Point);
}

bool SellCrossStillValid()
{
   double ma5[1], ma20[1];

   if(CopyBuffer(MA5Handle,0,0,1,ma5) < 1)
      return false;

   if(CopyBuffer(MA20Handle,0,0,1,ma20) < 1)
      return false;

  return (ma5[0] < ma20[0] &&
        (ma20[0] - ma5[0]) > 10 * _Point);
}

bool IsOneDollarMarket()
{
   return (
      StringFind(_Symbol, "Volatility 25 (1s) Index") >= 0 ||
      StringFind(_Symbol, "Volatility 15 Index") >= 0 ||
      StringFind(_Symbol, "Volatility 30 Index") >= 0 ||
      _Symbol == "XAUUSD"
   );
}
void CheckSmartProfitLock()
{
   if(BasketDirection == 0)
      return;

   double profit = GetBasketProfit();

   bool OneDollarMarkets = IsOneDollarMarket();

   //==================================================
   // AEGIS PROFIT MODE
   //==================================================

   AegisProfitMode ProfitMode = GetAegisProfitMode();

   //==================================================
// PRINT PROFIT MODE ONLY ONCE WHEN MODE CHANGES
//==================================================

if(!ProfitModePrintInitialized ||
   ProfitMode != LastPrintedProfitMode)
{
   if(ProfitMode == PROFIT_MODE_RUNNER)
      Print("PROFIT MODE: RUNNER");

   else if(ProfitMode == PROFIT_MODE_TIGHT)
      Print("PROFIT MODE: TIGHT");

   else if(ProfitMode == PROFIT_MODE_NORMAL)
      Print("PROFIT MODE: NORMAL");

   else
      Print("PROFIT MODE: UNKNOWN");

   LastPrintedProfitMode = ProfitMode;
   ProfitModePrintInitialized = true;
}


   //==================================================
   // $2 DRAWDOWN — ACTIVE FROM TRADE START
   //==================================================

   if(profit <= -2.00 &&
      !TwoDollarDrawdownReached)
   {
      TwoDollarDrawdownReached = true;

      PrintFormat(
         "2$ DRAWDOWN REACHED >>> Profit=%.2f | RECOVERY ARMED",
         profit
      );
   }


   //==================================================
   // RECOVERY EXIT
   //==================================================

   if(TwoDollarDrawdownReached &&
      profit > -0.50)
   {
      PrintFormat(
         "RECOVERY EXIT >>> Profit=%.3f",
         profit
      );

      CloseAllTrades();
      ResetBasket();
      SignalAlreadyTraded = true;

      return;
   }


   //==================================================
   // 180 SECOND HARD SL
   //==================================================

   if(HoldTimeFinished() &&
      profit <= -2.00)
   {
      PrintFormat(
         "2$ HARD SL HIT >>> Profit=%.2f | HoldTime=%d SEC",
         profit,
         (int)(TimeCurrent() - TradeOpenTime)
      );

      CloseAllTrades();
      ResetBasket();
      SignalAlreadyTraded = true;

      return;
   }


   //==================================================
   // RECOVERY DETECTION
   // WORKS IN ALL MODES
   //==================================================

   if(profit <= -0.40)
   {
      HadDeepDrawdown = true;
      RecoveryTrade = true;
   }


   //==================================================
   // RECOVERY REACHED
   //==================================================

   if(HadDeepDrawdown &&
      RecoveryTrade &&
      !RecoveryReached &&
      profit >= RecoveryLock)
   {
      RecoveryReached = true;

      PrintFormat(
         "RECOVERY REACHED >>> Profit=%.2f",
         profit
      );
   }


   //==================================================
   // START RECOVERY TIMER
   //==================================================

   if(HadDeepDrawdown &&
      RecoveryTrade &&
      !RecoveryLockActive &&
      RecoveryReached &&
      profit > RecoveryLock)
   {
      RecoveryLockActive = true;

      RecoveryTimerStarted = true;
      RecoveryStartTime = TimeCurrent();

      PrintFormat(
         "RECOVERY TIMER STARTED >>> Profit=%.2f | 30 SEC",
         profit
      );
   }


   //==================================================
   // UPDATE PEAK
   //==================================================

   if(profit > SmartProfitPeak)
      SmartProfitPeak = profit;


   //==================================================
   // RESET CURRENT PROFIT LOCK
   //==================================================

   SmartProfitLock = 0.0;


   //==================================================
   // RUNNER MODE
   //
   // STRONG TREND / STRONG REVERSAL
   //
   // NO GRACE
   // NO LOCK BELOW $1.00
   //==================================================

   if(ProfitMode == PROFIT_MODE_RUNNER)
{
   // Make absolutely sure Grace cannot interfere
   GraceTimerStarted = false;
   GraceTimerFinished = false;
   GraceStartTime = 0;
   GraceProtectedProfit = 0.0;

   // $1.00 -> $0.40
   if(SmartProfitPeak >= 1.00 &&
      SmartProfitPeak < 1.50)
   {
      SmartProfitLock = 0.40;
   }

   // $1.50 -> $1.00
   else if(SmartProfitPeak >= 1.50 &&
           SmartProfitPeak < 2.00)
   {
      SmartProfitLock = 1.00;
   }

   // $2.00 -> $1.40
   else if(SmartProfitPeak >= 2.00 &&
           SmartProfitPeak < 2.50)
   {
      SmartProfitLock = 1.40;
   }

   // $2.50 -> $1.90
   else if(SmartProfitPeak >= 2.50 &&
           SmartProfitPeak < 3.00)
   {
      SmartProfitLock = 1.90;
   }

   //==================================================
   // PRINT ONLY WHEN LOCK CHANGES
   //==================================================

   static double LastPrintedRunnerLock = -1.0;

   if(SmartProfitLock != LastPrintedRunnerLock)
   {
      PrintFormat(
         "RUNNER LOCK >>> Peak=%.2f | Lock=%.2f | TP=3.00",
         SmartProfitPeak,
         SmartProfitLock
      );

      LastPrintedRunnerLock = SmartProfitLock;
   }
}


   //==================================================
   // NORMAL MODE
   //
   // KEEP YOUR EXISTING NORMAL LOCK LADDER
   // GRACE ALLOWED
   //==================================================

   else if(ProfitMode == PROFIT_MODE_NORMAL)
   {
      if(!OneDollarMarkets)
      {
         if(SmartProfitPeak >= 0.50 &&
            SmartProfitPeak < 0.80)
         {
            SmartProfitLock = 0.10;
         }

         else if(SmartProfitPeak >= 0.80 &&
                 SmartProfitPeak < 1.00)
         {
            SmartProfitLock = 0.30;
         }
      }

      if(SmartProfitPeak >= 1.00 &&
         SmartProfitPeak < 1.30)
      {
         SmartProfitLock = 0.70;
      }

      else if(SmartProfitPeak >= 1.30 &&
              SmartProfitPeak < 1.50)
      {
         SmartProfitLock = 1.00;
      }

      else if(SmartProfitPeak >= 1.50 &&
              SmartProfitPeak < 1.90)
      {
         SmartProfitLock = 1.30;
      }

      else if(SmartProfitPeak >= 1.90 &&
              SmartProfitPeak < 2.00)
      {
         SmartProfitLock = 1.50;
      }

      else if(SmartProfitPeak >= 2.00 &&
              SmartProfitPeak < 2.30)
      {
         SmartProfitLock = 1.80;
      }

      else if(SmartProfitPeak >= 2.30 &&
              SmartProfitPeak < 2.50)
      {
         SmartProfitLock = 2.00;
      }

      else if(SmartProfitPeak >= 2.50 &&
              SmartProfitPeak < 2.90)
      {
         SmartProfitLock = 2.30;
      }

      else if(SmartProfitPeak >= 2.90)
      {
         SmartProfitLock = 2.50;
      }
   }


   //==================================================
   // TIGHT MODE
   //
   // $0.40 -> $0.15
   // $0.50 -> $0.20 + GRACE
   // $0.70 -> $0.40
   // $0.80-$0.99 -> $0.50
   //==================================================

   else if(ProfitMode == PROFIT_MODE_TIGHT)
   {
      if(SmartProfitPeak >= 0.40 &&
         SmartProfitPeak < 0.50)
      {
         SmartProfitLock = 0.15;
      }

      else if(SmartProfitPeak >= 0.50 &&
              SmartProfitPeak < 0.70)
      {
         SmartProfitLock = 0.20;
      }

      else if(SmartProfitPeak >= 0.70 &&
              SmartProfitPeak < 0.80)
      {
         SmartProfitLock = 0.40;
      }

      else if(SmartProfitPeak >= 0.80 &&
              SmartProfitPeak < 1.00)
      {
         SmartProfitLock = 0.50;
      }

      // From $1 onward use the normal higher-profit ladder
      else if(SmartProfitPeak >= 1.00 &&
              SmartProfitPeak < 1.30)
      {
         SmartProfitLock = 0.70;
      }

      else if(SmartProfitPeak >= 1.30 &&
              SmartProfitPeak < 1.50)
      {
         SmartProfitLock = 1.00;
      }

      else if(SmartProfitPeak >= 1.50 &&
              SmartProfitPeak < 1.90)
      {
         SmartProfitLock = 1.30;
      }

      else if(SmartProfitPeak >= 1.90 &&
              SmartProfitPeak < 2.00)
      {
         SmartProfitLock = 1.50;
      }

      else if(SmartProfitPeak >= 2.00 &&
              SmartProfitPeak < 2.30)
      {
         SmartProfitLock = 1.80;
      }

      else if(SmartProfitPeak >= 2.30 &&
              SmartProfitPeak < 2.50)
      {
         SmartProfitLock = 2.00;
      }

      else if(SmartProfitPeak >= 2.50 &&
              SmartProfitPeak < 2.90)
      {
         SmartProfitLock = 2.30;
      }

      else if(SmartProfitPeak >= 2.90)
      {
         SmartProfitLock = 2.50;
      }
   }


   //==================================================
   // GRACE TIMER
   //
   // ONLY NORMAL + TIGHT
   // NEVER RUNNER
   //==================================================

   if(EnableGraceTimer &&
      ProfitMode != PROFIT_MODE_RUNNER)
   {
      //==============================================
      // START GRACE AT $0.50
      //==============================================

      if(!GraceTimerStarted &&
         SmartProfitPeak >= 0.50)
      {
         GraceTimerStarted = true;
         GraceTimerFinished = false;
         GraceStartTime = TimeCurrent();

         if(ProfitMode == PROFIT_MODE_TIGHT)
            GraceProtectedProfit = 0.20;
         else
            GraceProtectedProfit = 0.15;
   GraceHoldingPrinted = false;
         PrintFormat(
            "GRACE TIMER STARTED >>> Mode=%s | Peak=%.2f | 30 SEC | Protected=%.2f",
            ProfitMode == PROFIT_MODE_TIGHT ? "TIGHT" : "NORMAL",
            SmartProfitPeak,
            GraceProtectedProfit
         );
      }


      //==============================================
      // UPGRADE AT $0.70
      //==============================================

      if(GraceTimerStarted &&
         SmartProfitPeak >= 0.70)
      {
         double NewProtection = 0.0;

         if(ProfitMode == PROFIT_MODE_TIGHT)
            NewProtection = 0.40;
         else
            NewProtection = 0.25;

         if(GraceProtectedProfit < NewProtection)
         {
            GraceProtectedProfit = NewProtection;

            PrintFormat(
               "GRACE PROTECTION UPGRADED >>> Peak=%.2f | Protected=%.2f",
               SmartProfitPeak,
               GraceProtectedProfit
            );
         }
      }


      //==============================================
      // APPLY GRACE PROTECTION
      //==============================================

      if(GraceTimerStarted &&
         GraceProtectedProfit > 0.0)
      {
         if(SmartProfitLock < GraceProtectedProfit)
            SmartProfitLock = GraceProtectedProfit;
      }
   }


   //==================================================
   // RECOVERY TIMER
   //
   // WORKS IN ALL THREE MODES
   //==================================================

   if(RecoveryTimerStarted)
   {
      //==============================================
      // $0.50 = RECOVERY CANCELLED
      //==============================================

      if(profit >= 0.50)
      {
         RecoveryTimerStarted = false;
         RecoveryLockActive = false;
         RecoveryReached = false;
         RecoveryTrade = false;
         RecoveryStartTime = 0;
         HadDeepDrawdown = false;

         PrintFormat(
            "RECOVERY CANCELLED >>> Profit=%.2f",
            profit
         );
      }

      //==============================================
      // +$0.15 = RECOVERY PASSED
      //==============================================

      else if(profit >= 0.15)
      {
         RecoveryTimerStarted = false;
         RecoveryLockActive = false;
         RecoveryReached = false;
         RecoveryTrade = false;
         RecoveryStartTime = 0;
         HadDeepDrawdown = false;

         PrintFormat(
            "RECOVERY PASSED >>> Profit=%.2f | Minimum=0.15",
            profit
         );
      }

      //==============================================
      // 30 SEC FAILED
      //==============================================

      else if(TimeCurrent() - RecoveryStartTime >= 30)
      {
         PrintFormat(
            "RECOVERY FAILED >>> Profit=%.2f | Required=0.15",
            profit
         );

         CloseAllTrades();
         ResetBasket();

         RecoveryTrade = false;
         RecoveryReached = false;
         RecoveryLockActive = false;
         RecoveryTimerStarted = false;
         RecoveryStartTime = 0;
         HadDeepDrawdown = false;

         SignalAlreadyTraded = true;

         return;
      }
   }


   //==================================================
   // 5 MINUTE CHECK
   //==================================================

   if(!Loss40SecExtension &&
      TimeCurrent() - TradeOpenTime >= 300)
   {
      if(profit > 0)
      {
         PrintFormat(
            "5 MIN PROFIT CLOSE >>> Profit=%.2f",
            profit
         );

         CloseAllTrades();
         ResetBasket();

         SignalAlreadyTraded = true;

         return;
      }

      Loss40SecExtension = true;
      Loss40SecStartTime = TimeCurrent();

      Print("5 MIN LOSS - 30 SEC EXTENSION STARTED");

      return;
   }


   //==================================================
   // 30 SECOND EXTENSION
   //==================================================

   if(Loss40SecExtension)
   {
      if(TimeCurrent() - Loss40SecStartTime >= 30)
      {
         Print("30 SEC EXTENSION FINISHED - FORCE CLOSE");

         CloseAllTrades();
         ResetBasket();

         SignalAlreadyTraded = true;

         return;
      }
   }


   //==================================================
   // GRACE TIMER EXPIRY
   // ONLY NORMAL + TIGHT
   //==================================================

   if(EnableGraceTimer &&
      ProfitMode != PROFIT_MODE_RUNNER &&
      GraceTimerStarted &&
      !GraceTimerFinished)
   {
      if(TimeCurrent() - GraceStartTime >= GraceTimerSeconds)
      {
         GraceTimerFinished = true;

         PrintFormat(
            "GRACE TIMER FINISHED >>> Mode=%s | Peak=%.2f | Protected=%.2f",
            ProfitMode == PROFIT_MODE_TIGHT ? "TIGHT" : "NORMAL",
            SmartProfitPeak,
            GraceProtectedProfit
         );
      }
   }


   //==================================================
   // SMART PROFIT LOCK
   //==================================================

   if(SmartProfitLock > 0 &&
      profit <= SmartProfitLock &&
      (!OneDollarMarkets ||
       SmartProfitPeak >= 1.00))
   {
      //==============================================
      // RUNNER
      // NO GRACE
      //==============================================

      if(ProfitMode == PROFIT_MODE_RUNNER)
      {
         PrintFormat(
            "RUNNER PROFIT LOCK >>> Peak=%.2f | Lock=%.2f | Profit=%.2f",
            SmartProfitPeak,
            SmartProfitLock,
            profit
         );

         CloseAllTrades();
         ResetBasket();

         SignalAlreadyTraded = true;

         return;
      }


      //==============================================
      // NORMAL / TIGHT
      // GRACE STILL RUNNING
      //==============================================

      if(EnableGraceTimer &&
   ProfitMode != PROFIT_MODE_RUNNER &&
   GraceTimerStarted &&
   !GraceTimerFinished)
{
   if(!GraceHoldingPrinted)
   {
      PrintFormat(
         "GRACE HOLDING >>> Mode=%s | Peak=%.2f | Lock=%.2f | Profit=%.2f",
         ProfitMode == PROFIT_MODE_TIGHT ? "TIGHT" : "NORMAL",
         SmartProfitPeak,
         SmartProfitLock,
         profit
      );

      GraceHoldingPrinted = true;
   }

   return;
}


      //==============================================
      // FINAL PROFIT LOCK
      //==============================================

      PrintFormat(
         "SMART PROFIT LOCK >>> Mode=%s | Peak=%.2f | Lock=%.2f | Profit=%.2f",
         ProfitMode == PROFIT_MODE_TIGHT ? "TIGHT" : "NORMAL",
         SmartProfitPeak,
         SmartProfitLock,
         profit
      );

      CloseAllTrades();
      ResetBasket();

      SignalAlreadyTraded = true;

      return;
   }
}


AegisProfitMode GetAegisProfitMode()
{
   //================================================
   // STRONG TREND SUPPORT
   //================================================

   if(CurrentMarketType == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_STRONG &&
      CurrentBehavior == BEHAVIOR_MOMENTUM)
   {
      return PROFIT_MODE_RUNNER;
   }

   if(CurrentMarketType == MARKET_TRENDING &&
      CurrentTrendStrength == STRENGTH_STRONG &&
      CurrentBehavior == BEHAVIOR_NORMAL)
   {
      return PROFIT_MODE_RUNNER;
   }

   //================================================
   // STRONG REVERSAL SUPPORT
   //================================================

   if(CurrentMarketBias == BIAS_REVERSAL)
   {
      bool reversalSupportsTrade = false;

      // BUY basket + AEGIS says BUY reversal
      if(BasketDirection == 1 &&
         CurrentTrendDirection == TREND_SELL)
      {
         reversalSupportsTrade = true;
      }

      // SELL basket + AEGIS says SELL reversal
      if(BasketDirection == -1 &&
         CurrentTrendDirection == TREND_BUY)
      {
         reversalSupportsTrade = true;
      }

      if(reversalSupportsTrade &&
         CurrentTrendStrength == STRENGTH_STRONG)
      {
         return PROFIT_MODE_RUNNER;
      }
   }

   //================================================
   // CAUTION CONDITIONS
   //================================================

   if(CurrentVolatility == VOL_EXTREME)
      return PROFIT_MODE_TIGHT;

   if(CurrentMarketType == MARKET_RANGING &&
      CurrentBehavior == BEHAVIOR_CHOPPY)
      return PROFIT_MODE_TIGHT;

   if(CurrentBehavior == BEHAVIOR_UNSTABLE)
      return PROFIT_MODE_TIGHT;

   if(CurrentMarketType == MARKET_RANGING &&
      CurrentVolatility == VOL_NORMAL &&
      CurrentBehavior == BEHAVIOR_MOMENTUM)
      return PROFIT_MODE_TIGHT;

   //================================================
   // NORMAL
   //================================================

   return PROFIT_MODE_NORMAL;
}



void DetectBuyHAFSCase()
{
  bool signalBull = iClose(_Symbol, PERIOD_M5, 0) >
                  iOpen(_Symbol, PERIOD_M5, 0);

bool signalBear = iClose(_Symbol, PERIOD_M5, 0) <
                  iOpen(_Symbol, PERIOD_M5, 0);

bool shift1Bull = iClose(_Symbol, PERIOD_M5, 1) >
                  iOpen(_Symbol, PERIOD_M5, 1);

bool shift1Bear = iClose(_Symbol, PERIOD_M5, 1) <
                  iOpen(_Symbol, PERIOD_M5, 1);

bool shift2Bull = iClose(_Symbol, PERIOD_M5, 2) >
                  iOpen(_Symbol, PERIOD_M5, 2);

bool shift2Bear = iClose(_Symbol, PERIOD_M5, 2) <
                  iOpen(_Symbol, PERIOD_M5, 2);

   if(shift1Bull && signalBull && shift2Bear)
   {
      CachedHAFSCase = BUY1_REV;
      Print("HAFS BUY CASE 1 REVERSAL");
   }
   else if(shift1Bull && signalBull)
   {
      CachedHAFSCase = BUY1;
      Print("BUY CASE 1");
   }
   else if(shift1Bull && signalBear && shift2Bear)
   {
      CachedHAFSCase = BUY2;
      Print("HAFS BUY CASE 2");
   }
   else if(shift1Bull && signalBear && shift2Bull)
   {
      CachedHAFSCase = BUY5;
      Print("HAFS BUY CASE 5");
   }
   else if(shift1Bear && signalBull && shift2Bear)
   {
      CachedHAFSCase = BUY3;
      Print("HAFS BUY CASE 3");
   }
   else if(shift1Bear && signalBull && shift2Bull)
   {
      CachedHAFSCase = BUY6;
      Print("HAFS BUY CASE 6");
   }
   else if(shift1Bear && signalBear && shift2Bull)
   {
      CachedHAFSCase = BUY4_REV;
      Print("HAFS BUY CASE 4 REVERSAL");
   }
   else if(shift1Bear && signalBear && shift2Bear)
   {
      CachedHAFSCase = BUY4;
      Print("BUY CASE 4");
   }
}
void DetectSellHAFSCase()
{
  bool signalBull = iClose(_Symbol, PERIOD_M5, 0) >
                  iOpen(_Symbol, PERIOD_M5, 0);

bool signalBear = iClose(_Symbol, PERIOD_M5, 0) <
                  iOpen(_Symbol, PERIOD_M5, 0);

bool shift1Bull = iClose(_Symbol, PERIOD_M5, 1) >
                  iOpen(_Symbol, PERIOD_M5, 1);

bool shift1Bear = iClose(_Symbol, PERIOD_M5, 1) <
                  iOpen(_Symbol, PERIOD_M5, 1);

bool shift2Bull = iClose(_Symbol, PERIOD_M5, 2) >
                  iOpen(_Symbol, PERIOD_M5, 2);

bool shift2Bear = iClose(_Symbol, PERIOD_M5, 2) <
                  iOpen(_Symbol, PERIOD_M5, 2);

   if(shift1Bear && signalBear && shift2Bear)
   {
      CachedHAFSCase = SELL1;
      Print("SELL CASE 1");
   }
   else if(shift1Bear && signalBear && shift2Bull)
   {
      CachedHAFSCase = SELL1_REV;
      Print("HAFS SELL CASE 1 REVERSAL");
   }
   else if(shift1Bull && signalBear && shift2Bull)
   {
      CachedHAFSCase = SELL2;
      Print("HAFS SELL CASE 2");
   }
   else if(shift1Bull && signalBear && shift2Bear)
   {
      CachedHAFSCase = SELL5;
      Print("HAFS SELL CASE 5");
   }
   else if(shift1Bear && signalBull && shift2Bull)
   {
      CachedHAFSCase = SELL3;
      Print("HAFS SELL CASE 3");
   }
   else if(shift1Bear && signalBull && shift2Bear)
   {
      CachedHAFSCase = SELL6;
      Print("HAFS SELL CASE 6");
   }
   else if(shift1Bull && signalBull && shift2Bear)
   {
      CachedHAFSCase = SELL4_REV;
      Print("HAFS SELL CASE 4 REVERSAL");
   }
   else if(shift1Bull && signalBull)
   {
      CachedHAFSCase = SELL4;
      Print("SELL CASE 4");
   }
}


void DetectHAFSCase()
{
 //  if(CachedCaseDetected)
 //  return;
datetime currentHAFSCandle = iTime(_Symbol, PERIOD_M5, 0);

if(currentHAFSCandle == LastHAFSCandle)
{
   return;
}

   //================ GET CANDLE STATES ================

  bool signalBull =
   iClose(_Symbol, PERIOD_M5,0) >
   iOpen(_Symbol, PERIOD_M5,0);

bool signalBear =
   iClose(_Symbol, PERIOD_M5,0) <
   iOpen(_Symbol, PERIOD_M5,0);

bool shift1Bull =
   iClose(_Symbol, PERIOD_M5,1) >
   iOpen(_Symbol, PERIOD_M5,1);

bool shift1Bear =
   iClose(_Symbol, PERIOD_M5,1) <
   iOpen(_Symbol, PERIOD_M5,1);

bool shift2Bull =
   iClose(_Symbol, PERIOD_M5,2) >
   iOpen(_Symbol, PERIOD_M5,2);

bool shift2Bear =
   iClose(_Symbol, PERIOD_M5,2) <
   iOpen(_Symbol, PERIOD_M5,2);
Print(
   "HAFS MAP | ",
   "Signal=", (signalBull ? "BUY" : signalBear ? "SELL" : "DOJI"),
   " B=", (shift1Bull ? "BUY" : shift1Bear ? "SELL" : "DOJI"),
   " C=", (shift2Bull ? "BUY" : shift2Bear ? "SELL" : "DOJI")
);
   Print(
      "HAFS => ",
      " signalBull=",signalBull,
      " signalBear=",signalBear,
      " shift1Bull=",shift1Bull,
      " shift1Bear=",shift1Bear,
      " shift2Bull=",shift2Bull,
      " shift2Bear=",shift2Bear
   );


   // Reset cache

   CachedHAFSCase = 0;

// Route detection by cached trend
if(CrossDirection == 1)
{
   DetectBuyHAFSCase();
}
else if(CrossDirection == -1)
{
   DetectSellHAFSCase();
}
if(CachedHAFSCase != CASE_NONE)
{
   CachedCaseDetected = true;

   LastHAFSCandle = currentHAFSCandle;

   Print("HAFS CASE CACHED = ", CachedHAFSCase);
}
}
void ExecuteHAFSCase()
{
Print("ExecuteHAFSCase ENTER");
Print("CurrentHAFSCase = ", CurrentHAFSCase);
Print("CachedHAFSCase = ", CachedHAFSCase);
bool WickBuy  = CachedAWickBuy;
bool WickSell = CachedAWickSell;
   switch(CurrentHAFSCase)
   {
      case BUY1_REV:
      {
         
    Print("HAFS BUY CASE 1 REVERSAL");

   bool A = WickSell;
bool B = CachedBSellWick;
bool C = CachedCSellWick;

   // ================ MINIMUM WICK SIZE FILTER ================

  double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY1 REV: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY1 REV: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
   // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("BUY1 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("BUY1 REV: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1 REV: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}

return;

         break;
      }

     case BUY1:
{
    Print("BUY CASE 1");

    bool A = WickBuy;
    bool B = CachedBBuyWick;
    bool C = CachedCBuyWick;

  // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY1: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }   

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY1 : Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

    //================= PHOENIX MASTERMIND =================

    if(A)
    {
        if(B)
        {
            if(C)
            {
                Print("BUY1: A✓ B✓ C✓ -> BUY");
                AegisFinalDecision(1);
            }
            else
            {
                Print("BUY1: A✓ B✓ C✗ -> SELL");
                AegisFinalDecision(-1);
            }
        }
        else
        {
            if(C)
            {
                Print("BUY1: A✓ B✗ C✓ -> BUY");
                AegisFinalDecision(1);
            }
            else
            {
                Print("BUY1: A✓ B✗ C✗ -> SELL");
                AegisFinalDecision(-1);
            }
        }
    }
    else
    {
        if(B)
        {
            if(C)
            {
                Print("BUY1: A✗ B✓ C✓ -> BUY");
                AegisFinalDecision(1);
            }
            else
            {
                Print("BUY1: A✗ B✓ C✗ -> SELL");
                AegisFinalDecision(-1);
            }
        }
        else
        {
            if(C)
            {
                Print("BUY1: A✗ B✗ C✓ -> BUY");
                AegisFinalDecision(1);
            }
            else
            {
                Print("BUY1: A✗ B✗ C✗ -> SELL");
                AegisFinalDecision(-1);
            }
        }
    }

    return;
}
break;
   
   case BUY2:
{
   Print("HAFS BUY CASE 2");

   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;
 // ================ MINIMUM WICK SIZE FILTER ================

  double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY2: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY2: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

   //================ PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY2: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY2: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY2: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY2: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY2: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("BUY2: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY2: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("BUY2: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }

   return;
}
break;

case BUY5:
{
   Print("HAFS BUY CASE 5");

   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY5: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY5: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

   //================ PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY5: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY5: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY5: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY5: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY5: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY5: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY5: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY5: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case BUY3:
{
   Print("HAFS BUY CASE 3");

   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY3: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY3: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
   

   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY3: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY3: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY3: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY3: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY3: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY3: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY3: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY3: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case BUY6:
{
   Print("HAFS BUY CASE 6");

   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY6: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY6: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
   


   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY6: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY6: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY6: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY6: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY6: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY6: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY6: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY6: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;
 
case BUY4_REV:
{
   Print("HAFS BUY CASE 4 REVERSAL");

   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY4 REV: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY4 REV: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY4 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("BUY4 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY4 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("BUY4 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY4 REV: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4 REV: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY4 REV: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4 REV: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case BUY4:
{
   Print("BUY CASE 4");


   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY4: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "BUY4: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
  
   // ================= BUY4 MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("BUY4: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY4: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("BUY4: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("BUY4: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("BUY4: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;


case SELL1:
{
   Print("SELL CASE 1");


   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL1: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL1: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
  


   // ================= SELL1 MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL1: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL1: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL1: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL1: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case SELL1_REV:
{
   Print("HAFS SELL CASE 1 REVERSAL");


   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL1 REV: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL1 REV: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}



   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL1 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL1 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL1 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL1 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL1 REV: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1 REV: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL1 REV: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL1 REV: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case SELL2:
{
   Print("HAFS SELL CASE 2");


   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL2: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL2: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

  


   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL2: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL2: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL2: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL2: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL2: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL2: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL2: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL2: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case SELL5:
{
   Print("HAFS SELL CASE 5");


   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;
 // ================ MINIMUM WICK SIZE FILTER ================

  double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL5: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL5: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
  
   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL5: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL5: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL5: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL5: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL5: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL5: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL5: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL5: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }

   return;
}
break;

case SELL3:
{
   Print("HAFS SELL CASE 3");


   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL3: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL3: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

  

   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL3: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL3: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL3: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL3: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL3: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL3: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL3: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL3: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;

case SELL6:
{
   Print("HAFS SELL CASE 6");


   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;
 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL6: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL6: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}

  

   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL6: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL6: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL6: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL6: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL6: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL6: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL6: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
         }
         else
         {
            Print("SELL6: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
         }
      }
   }

   return;
}
break;
 
case SELL4_REV:
{
   Print("HAFS SELL CASE 4 REVERSAL");


   bool A = WickSell;
   bool B = CachedBSellWick;
   bool C = CachedCSellWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL4 REV: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL4 REV: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
  

   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL4 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL4 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL4 REV: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4 REV: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL4 REV: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4 REV: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }

   return;
}
break;

case SELL4:
{
   Print("SELL CASE 4");


   bool A = WickBuy;
   bool B = CachedBBuyWick;
   bool C = CachedCBuyWick;

 // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = CachedAUpperWick + CachedALowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL4: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }
double CandleStrength = CachedCandleStrength;

if(CandleStrength < MinimumCandleStrengthPercent)
{
   PrintFormat(
      "SELL4: Trade Rejected - Candle Strength %.1f%%",
      CandleStrength
   );
   return;
}
  


   // ================= PHOENIX MASTERMIND =================

   if(A)
   {
      if(B)
      {
         if(C)
         {
            Print("SELL4: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL4: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }
   else
   {
      if(B)
      {
         if(C)
         {
            Print("SELL4: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
      else
      {
         if(C)
         {
            Print("SELL4: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
         }
         else
         {
            Print("SELL4: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
         }
      }
   }

   return;
}
break;

}
}
bool CalculateBrokerSLTP(
   bool isBuy,
   double entryPrice,
   double volume,
   double &slPrice,
   double &tpPrice
)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickValueLoss = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double tickValueProfit = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);

   if(tickValueLoss <= 0.0)
      tickValueLoss = tickValue;

   if(tickValueProfit <= 0.0)
      tickValueProfit = tickValue;

   if(tickSize <= 0.0 ||
      tickValueLoss <= 0.0 ||
      tickValueProfit <= 0.0 ||
      volume <= 0.0 ||
      BasketSL <= 0.0 ||
      BasketTP <= 0.0 ||
      entryPrice <= 0.0)
   {
      Print("SL/TP CALCULATION FAILED: Invalid symbol or money values.");
      return false;
   }

   // Convert the monetary SL/TP targets into price distances.
   double slDistance =
      (BasketSL / (tickValueLoss * volume)) * tickSize;

   double tpDistance =
      (BasketTP / (tickValueProfit * volume)) * tickSize;

   // Respect the broker's minimum stop distance.
   long stopsLevel =
      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   double minDistance = stopsLevel * _Point;

   // Add one tick as a small safety buffer.
   minDistance += tickSize;

   if(slDistance < minDistance)
      slDistance = minDistance;

   if(tpDistance < minDistance)
      tpDistance = minDistance;

   if(isBuy)
   {
      // Round outward to valid tick-size increments.
      slPrice = MathFloor((entryPrice - slDistance) / tickSize) * tickSize;
      tpPrice = MathCeil ((entryPrice + tpDistance) / tickSize) * tickSize;
   }
   else
   {
      slPrice = MathCeil ((entryPrice + slDistance) / tickSize) * tickSize;
      tpPrice = MathFloor((entryPrice - tpDistance) / tickSize) * tickSize;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   slPrice = NormalizeDouble(slPrice, digits);
   tpPrice = NormalizeDouble(tpPrice, digits);

   if(slPrice <= 0.0 || tpPrice <= 0.0)
   {
      Print("SL/TP CALCULATION FAILED: Invalid resulting prices.");
      return false;
   }

   PrintFormat(
      "BROKER SL/TP CALCULATED | SL=%.5f | TP=%.5f | SL TARGET=$%.2f | TP TARGET=$%.2f",
      slPrice,
      tpPrice,
      BasketSL,
      BasketTP
   );

   return true;
}
void ExecuteBuyTrade()
{

   MqlTick reqTick;

   if(!SymbolInfoTick(_Symbol, reqTick))
      return;

   long buyRequestServerMs = (long)reqTick.time_msc;

   long buyRequestAgeMs =
      buyRequestServerMs -
      (long)SignalCandleTime * 1000;

   PrintFormat(
      "BUY REQUEST SENT -> CANDLE AGE=%.3f SEC",
      buyRequestAgeMs / 1000.0
   );

  double buySL = 0.0;
double buyTP = 0.0;

double buyEntryPrice = reqTick.ask;

if(!CalculateBrokerSLTP(
      true,
      buyEntryPrice,
      LotSize,
      buySL,
      buyTP))
{
   Print("BUY CANCELLED: Could not calculate broker SL/TP.");
   return;
}

bool buyResult = trade.Buy(
   LotSize,
   _Symbol,
   0.0,
   buySL,
   buyTP
);

   MqlTick postTick;

   if(SymbolInfoTick(_Symbol, postTick))
   {
      long buyResultServerMs = (long)postTick.time_msc;

      long buyResultAgeMs =
         buyResultServerMs -
         (long)SignalCandleTime * 1000;

      PrintFormat(
         "BUY ORDER RESULT -> CANDLE AGE=%.3f SEC | RESULT=%s | RETCODE=%d",
         buyResultAgeMs / 1000.0,
         buyResult ? "SUCCESS" : "FAILED",
         trade.ResultRetcode()
      );
   }

   if(buyResult)
   {
      BasketDirection = 1;
      TradeOpenTime = TimeCurrent();
      TradeOpenBar = iTime(_Symbol, PERIOD_M5, 0);
      SignalAlreadyTraded = true;

      Print("BUY EXECUTED");

      Print(
         "Trade Open Bar Saved: ",
         TradeOpenBar
      );
   }
   else
   {
      PrintFormat(
         "BUY FAILED -> RETCODE=%d | %s",
         trade.ResultRetcode(),
         trade.ResultRetcodeDescription()
      );
   }
}


void ExecuteSellTrade()
{
   MqlTick reqTick;

   if(!SymbolInfoTick(_Symbol, reqTick))
      return;

   long sellRequestServerMs = (long)reqTick.time_msc;

   long sellRequestAgeMs =
      sellRequestServerMs -
      (long)SignalCandleTime * 1000;

   PrintFormat(
      "SELL REQUEST SENT -> CANDLE AGE=%.3f SEC",
      sellRequestAgeMs / 1000.0
   );

  double sellSL = 0.0;
double sellTP = 0.0;

double sellEntryPrice = reqTick.bid;

if(!CalculateBrokerSLTP(
      false,
      sellEntryPrice,
      LotSize,
      sellSL,
      sellTP))
{
   Print("SELL CANCELLED: Could not calculate broker SL/TP.");
   return;
}

bool sellResult = trade.Sell(
   LotSize,
   _Symbol,
   0.0,
   sellSL,
   sellTP
);

   MqlTick postTick;

   if(SymbolInfoTick(_Symbol, postTick))
   {
      long sellResultServerMs = (long)postTick.time_msc;

      long sellResultAgeMs =
         sellResultServerMs -
         (long)SignalCandleTime * 1000;

      PrintFormat(
         "SELL ORDER RESULT -> CANDLE AGE=%.3f SEC | RESULT=%s | RETCODE=%d",
         sellResultAgeMs / 1000.0,
         sellResult ? "SUCCESS" : "FAILED",
         trade.ResultRetcode()
      );
   }

   if(sellResult)
   {
      BasketDirection = -1;
      TradeOpenTime = TimeCurrent();
      TradeOpenBar = iTime(_Symbol, PERIOD_M5, 0);
      SignalAlreadyTraded = true;

      Print("SELL EXECUTED");

      Print(
         "Trade Open Bar Saved: ",
         TradeOpenBar
      );
   }
   else
   {
      PrintFormat(
         "SELL FAILED -> RETCODE=%d | %s",
         trade.ResultRetcode(),
         trade.ResultRetcodeDescription()
      );
   }
}


void CloseTradeOnCandleClose()
{
   if(!PositionSelect(_Symbol))
      return;

   if(TradeOpenBar == 0)
      return;

   datetime CurrentBar = iTime(_Symbol, PERIOD_M5, 0);

   // A new M5 candle has started
   if(CurrentBar > TradeOpenBar)
   {
      Print(">>> Closing trade after one completed M5 candle");

      if(trade.PositionClose(_Symbol))
      {
         TradeOpenBar = 0;
      }
   }
}

bool HAFS_ThreeCandleWickFilter(bool &reverseToSell)
{
   bool signalBuyWick  = WickConfirmation(true);
   bool signalSellWick = WickConfirmation(false);

   bool B_Buy  = CandleBSupportsBuyWick();
   bool B_Sell = CandleBSupportsSellWick();

   bool C_Buy  = CandleCSupportsBuyWick();
   bool C_Sell = CandleCSupportsSellWick();


   // A+B+C all support BUY -> SELL
   if(signalBuyWick && B_Buy && C_Buy)
   {
      Print(">>> NEW HAFS FILTER: A+B+C BUY wick -> SELL");
      reverseToSell = true;
      return true;
   }


   // A+B+C all support SELL -> BUY
   if(signalSellWick && B_Sell && C_Sell)
   {
      Print(">>> NEW HAFS FILTER: A+B+C SELL wick -> BUY");
      reverseToSell = false;
      return true;
   }

   return false;
}
void UpdateAegis()
{
   CurrentMarketType      = GetMarketType();
   CurrentTrendDirection  = GetTrendDirection();
   CurrentTrendStrength   = GetTrendStrength();
   CurrentVolatility      = GetVolatilityState();
   CurrentBehavior        = GetMarketBehavior();

   CurrentDecision        = CalculateAegisDecision();
}
//================ AEGIS FINAL DECISION ================

void AegisFinalDecision(int direction)
{
   TradeType tradeType = TRADE_UNKNOWN;

   //================ REVERSAL CASES =================

   switch(CurrentHAFSCase)
   {
      case BUY1_REV:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL1_REV:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case BUY4_REV:

         if(direction == 1)
            tradeType = TRADE_REVERSAL;
         else
            tradeType = TRADE_TREND;

         break;

      case SELL4_REV:

         if(direction == -1)
            tradeType = TRADE_REVERSAL;
         else
            tradeType = TRADE_TREND;

         break;
   }

   //================ TREND CASES =================

   switch(CurrentHAFSCase)
   {
      case BUY1:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case BUY4:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL1:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL4:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;
   }

   //================ PATTERN CASES =================

   switch(CurrentHAFSCase)
   {
      case BUY2:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case BUY3:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL2:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL3:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case BUY5:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case BUY6:

         if(direction == -1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL5:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;

      case SELL6:

         if(direction == 1)
            tradeType = TRADE_TREND;
         else
            tradeType = TRADE_REVERSAL;

         break;
   }

   //================ UPDATE AEGIS DATA =================

   CurrentMarketType      = CachedMarketType;
   CurrentTrendDirection  = CachedTrendDirection;
   CurrentTrendStrength   = CachedTrendStrength;
   CurrentVolatility      = CachedVolatility;
   CurrentBehavior        = CachedBehavior;

   Print("AEGIS DATA | Market:",
         CurrentMarketType,
         " Trend:",
         CurrentTrendDirection,
         " Strength:",
         CurrentTrendStrength,
         " Volatility:",
         CurrentVolatility,
         " Behavior:",
         CurrentBehavior);

   //==================================================
   // AEGIS TREND STRENGTH
   //==================================================

   if(CurrentTrendStrength == STRENGTH_STRONG)
      Print("AEGIS TREND STRENGTH: STRONG");
   else if(CurrentTrendStrength == STRENGTH_NORMAL)
      Print("AEGIS TREND STRENGTH: NORMAL");
   else
      Print("AEGIS TREND STRENGTH: WEAK");

   //==================================================
   // AEGIS REVERSAL STRENGTH
   //==================================================

   CachedReversalStrength = CalculateReversalStrength();
   CurrentReversalStrength = CachedReversalStrength;

   if(CurrentReversalStrength == REVERSAL_STRONG)
      Print("AEGIS REVERSAL STRENGTH: STRONG");
   else if(CurrentReversalStrength == REVERSAL_NORMAL)
      Print("AEGIS REVERSAL STRENGTH: NORMAL");
   else
      Print("AEGIS REVERSAL STRENGTH: WEAK");

   //==================================================
   // AEGIS TRADE TYPE
   //==================================================

   if(tradeType == TRADE_TREND)
      Print("AEGIS TYPE: TREND");

   if(tradeType == TRADE_REVERSAL)
      Print("AEGIS TYPE: REVERSAL");

   if(tradeType == TRADE_UNKNOWN)
   {
      Print("AEGIS: UNKNOWN TRADE TYPE - BLOCKED");
      return;
   }

   //================ AEGIS DECISION =================

   AegisDecision decision = CachedAegisDecision;

   CurrentMarketBias = CachedMarketBias;

   PrintAegisPreferredTrade();

   //==================================================
   // AEGIS PREFERRED TRADE + STRENGTH
   //
   // BIAS
   //   ↓
   // PREFERRED TRADE
   //   ↓
   // TREND     → TrendStrength
   // REVERSAL  → ReversalStrength
   //   ↓
   // STRONG / NORMAL / WEAK
   //==================================================

   bool AegisStrongPreferred = false;
   bool AegisNormalPreferred = false;
   bool AegisWeakPreferred   = false;

   //==================================================
   // TREND BIAS
   //==================================================

   if(CurrentMarketBias == BIAS_TREND)
   {
      if(CurrentTrendDirection == TREND_BUY)
      {
         Print("AEGIS PREFERRED TYPE: BUY TREND");

         if(CurrentTrendStrength == STRENGTH_STRONG)
         {
            AegisStrongPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: STRONG");
         }
         else if(CurrentTrendStrength == STRENGTH_NORMAL)
         {
            AegisNormalPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: NORMAL");
         }
         else
         {
            AegisWeakPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: WEAK");
         }
      }
      else if(CurrentTrendDirection == TREND_SELL)
      {
         Print("AEGIS PREFERRED TYPE: SELL TREND");

         if(CurrentTrendStrength == STRENGTH_STRONG)
         {
            AegisStrongPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: STRONG");
         }
         else if(CurrentTrendStrength == STRENGTH_NORMAL)
         {
            AegisNormalPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: NORMAL");
         }
         else
         {
            AegisWeakPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: WEAK");
         }
      }
   }

   //==================================================
   // REVERSAL BIAS
   //==================================================

   else if(CurrentMarketBias == BIAS_REVERSAL)
   {
      if(CurrentTrendDirection == TREND_BUY)
      {
         Print("AEGIS PREFERRED TYPE: SELL REVERSAL");

         if(CurrentReversalStrength == REVERSAL_STRONG)
         {
            AegisStrongPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: STRONG");
         }
         else if(CurrentReversalStrength == REVERSAL_NORMAL)
         {
            AegisNormalPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: NORMAL");
         }
         else
         {
            AegisWeakPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: WEAK");
         }
      }
      else if(CurrentTrendDirection == TREND_SELL)
      {
         Print("AEGIS PREFERRED TYPE: BUY REVERSAL");

         if(CurrentReversalStrength == REVERSAL_STRONG)
         {
            AegisStrongPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: STRONG");
         }
         else if(CurrentReversalStrength == REVERSAL_NORMAL)
         {
            AegisNormalPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: NORMAL");
         }
         else
         {
            AegisWeakPreferred = true;
            Print("AEGIS PREFERRED STRENGTH: WEAK");
         }
      }
   }

   //================ MARKET BIAS DEBUG =================

   if(CurrentMarketBias == BIAS_TREND)
      Print("AEGIS MARKET BIAS: TREND");

   if(CurrentMarketBias == BIAS_REVERSAL)
      Print("AEGIS MARKET BIAS: REVERSAL");

   if(CurrentMarketBias == BIAS_UNKNOWN)
      Print("AEGIS MARKET BIAS: UNKNOWN");

   //================ REJECT =================

   if(decision == DECISION_REJECT)
   {
      Print("AEGIS: MARKET REJECTED");
      return;
   }

   //================ UNKNOWN BIAS =================

   if(CurrentMarketBias == BIAS_UNKNOWN)
   {
      Print("AEGIS: UNKNOWN MARKET BIAS");
      return;
   }

   //================ CAUTION =================

   if(decision == DECISION_CAUTION &&
      tradeType == TRADE_TREND)
   {
      Print("AEGIS: Trend Trade Caution - Blocked");
      return;
   }

   //================ FINAL DIRECTION =================

   int CalculatedFinalDirection = direction;

   double CandleStrength = CachedCandleStrength;

   bool ExtremeCandle =
   (CandleStrength < 10.0);

   // EXTREME CANDLE
// BELOW 10% ONLY

   if(ExtremeCandle)
   {
      if(CurrentMarketBias == BIAS_REVERSAL)
      {
         CalculatedFinalDirection = -direction;

         PrintFormat(
            "AEGIS: EXTREME CANDLE REVERSAL >>> Strength=%.1f%%",
            CandleStrength
         );

         Print("AEGIS: BIAS = REVERSAL -> REVERSAL TRADE");
      }
      else if((tradeType == TRADE_TREND &&
               CurrentMarketBias == BIAS_REVERSAL) ||
              (tradeType == TRADE_REVERSAL &&
               CurrentMarketBias == BIAS_TREND))
      {
         CalculatedFinalDirection = -direction;

         Print("AEGIS: TRADE TYPE != MARKET BIAS");
         Print("AEGIS: SIGNAL REVERSED");
      }
      else
      {
         CalculatedFinalDirection = -direction;

         Print("AEGIS: EXTREME CANDLE -> SIGNAL KEPT");
      }
   }

   //==================================================
   // NORMAL CANDLE
   // 10% - 69%
   //
   // STRONG  → AEGIS PREFERRED
   // NORMAL  → AEGIS PREFERRED
   // WEAK    → HAFS / ORIGINAL
   //==================================================

   else
   {
      //================================================
      // STRONG / NORMAL
      // AEGIS PREFERRED HAS AUTHORITY
      //================================================

      if(AegisStrongPreferred || AegisNormalPreferred)
      {
         //=============================================
         // TREND PREFERRED
         //=============================================

         if(CurrentMarketBias == BIAS_TREND)
         {
            if(CurrentTrendDirection == TREND_BUY)
            {
               CalculatedFinalDirection = 1;

               if(AegisStrongPreferred)
                  Print("AEGIS STRONG -> BUY TREND");
               else
                  Print("AEGIS NORMAL -> BUY TREND");
            }
            else if(CurrentTrendDirection == TREND_SELL)
            {
               CalculatedFinalDirection = -1;

               if(AegisStrongPreferred)
                  Print("AEGIS STRONG -> SELL TREND");
               else
                  Print("AEGIS NORMAL -> SELL TREND");
            }
            else
            {
               CalculatedFinalDirection = direction;
               Print("AEGIS TREND DIRECTION UNKNOWN -> HAFS");
            }
         }

         //=============================================
         // REVERSAL PREFERRED
         //=============================================

         else if(CurrentMarketBias == BIAS_REVERSAL)
         {
            if(CurrentTrendDirection == TREND_BUY)
            {
               // BUY trend -> SELL reversal

               CalculatedFinalDirection = -1;

               if(AegisStrongPreferred)
                  Print("AEGIS STRONG -> SELL REVERSAL");
               else
                  Print("AEGIS NORMAL -> SELL REVERSAL");
            }
            else if(CurrentTrendDirection == TREND_SELL)
            {
               // SELL trend -> BUY reversal

               CalculatedFinalDirection = 1;

               if(AegisStrongPreferred)
                  Print("AEGIS STRONG -> BUY REVERSAL");
               else
                  Print("AEGIS NORMAL -> BUY REVERSAL");
            }
            else
            {
               CalculatedFinalDirection = direction;
               Print("AEGIS REVERSAL DIRECTION UNKNOWN -> HAFS");
            }
         }
      }

      //================================================
      // WEAK
      // HAFS / ORIGINAL DIRECTION HAS AUTHORITY
      //================================================

      else if(AegisWeakPreferred)
      {
         CalculatedFinalDirection = direction;

         PrintFormat(
            "AEGIS WEAK -> HAFS ORIGINAL >>> Direction=%s",
            direction == 1 ? "BUY" : "SELL"
         );
      }

      //================================================
      // UNKNOWN
      //================================================

      else
      {
         CalculatedFinalDirection = direction;

         Print("AEGIS STRENGTH UNKNOWN -> HAFS ORIGINAL");
      }
   }

   //================ FREEZE FINAL DIRECTION =================

   FinalDirection = CalculatedFinalDirection;

   if(FinalDirection == 1)
   {
      Print("AEGIS FINAL FROZEN: BUY");
   }
   else if(FinalDirection == -1)
   {
      Print("AEGIS FINAL FROZEN: SELL");
   }
   else
   {
      Print("AEGIS FINAL FROZEN: UNKNOWN");
   }

   if(FreezeOnlyMode)
      return;
}
//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{

// CloseTradeOnCandleClose();
   // New bar detection
  datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
bool newBar = (currentBarTime != LastBarTime);

if(newBar)
{
   PreProcessStarted = false;

   //==================================================
   // SAVE EXACT LOCAL START OF NEW M5 CANDLE
   //==================================================

   SignalCandleStartLocalMs = GetMicrosecondCount() / 1000;

   LastBarTime = currentBarTime;

   if(!CrossDetected)
      CrossSeenThisCandle = false;
}


   double profit = GetBasketProfit();
   CheckSmartProfitLock();
   int cross = DetectCross();

 //--- STEP 1: Detect cross DURING any forming candle (every tick)
   //    Record which direction the cross is happening
 
if(!CrossDetected &&
   BasketDirection == 0 &&
   !CrossSeenThisCandle)

{
   double ma200now[1], ma5now[1], ma20now[1];

   if(CopyBuffer(MA200Handle,0,0,1,ma200now) != 1)
   {
      Print("MA200 CopyBuffer Failed");
      return;
   }

   if(CopyBuffer(MA5Handle,0,0,1,ma5now) != 1)
   {
      Print("MA5 CopyBuffer Failed");
      return;
   }

   if(CopyBuffer(MA20Handle,0,0,1,ma20now) != 1)
   {
      Print("MA20 CopyBuffer Failed");
      return;
   }

   bool ma200Above = (ma5now[0] < ma200now[0] || ma20now[0] < ma200now[0]);
bool ma200Below = (ma5now[0] > ma200now[0] || ma20now[0] > ma200now[0]);

  //==========================================================
   // BUY CROSS
   //==========================================================

  if(cross == 1)
{
   Print("BUY CROSS DETECTED");

  

   

CrossDetected      = true;
CrossSeenThisCandle = true;
HAFSSignalSymbol   = _Symbol;
CrossDirection     = 1;

SignalCandleTime = iTime(_Symbol, PERIOD_M5, 0);

SignalCandleStartMs =
   (GetMicrosecondCount() / 1000)
   - ((TimeCurrent() - SignalCandleTime) * 1000);

LastCrossTime = TimeCurrent();
      
      //================ CANDLE B =================
      double o = iOpen(_Symbol, PERIOD_M5, 1);
      double c = iClose(_Symbol, PERIOD_M5, 1);
      double h = iHigh(_Symbol, PERIOD_M5, 1);
      double l = iLow(_Symbol, PERIOD_M5, 1);

      SavedUpperWick = h - MathMax(o, c);
      SavedLowerWick = MathMin(o, c) - l;

      //================ CANDLE C =================
      double oC = iOpen(_Symbol, PERIOD_M5, 2);
      double cC = iClose(_Symbol, PERIOD_M5, 2);
      double hC = iHigh(_Symbol, PERIOD_M5, 2);
      double lC = iLow(_Symbol, PERIOD_M5, 2);

      SavedCUpperWick = hC - MathMax(oC, cC);
      SavedCLowerWick = MathMin(oC, cC) - lC;

      SavedCandleBull = (c > o);
      SavedCandleBear = (c < o);

      SavedSpecialData = true;

      Print("SPECIAL CANDLE B & C SAVED");
      return;
   }

   //==========================================================
   // SELL CROSS
   //==========================================================

 if(cross == -1)
{
   Print("SELL CROSS DETECTED");

  CrossDetected      = true;
CrossSeenThisCandle = true;
HAFSSignalSymbol   = _Symbol;
CrossDirection     = -1;

SignalCandleTime = iTime(_Symbol, PERIOD_M5, 0);

SignalCandleStartMs =
   (GetMicrosecondCount() / 1000)
   - ((TimeCurrent() - SignalCandleTime) * 1000);

LastCrossTime = TimeCurrent();

      //================ CANDLE B =================
      double o = iOpen(_Symbol, PERIOD_M5, 1);
      double c = iClose(_Symbol, PERIOD_M5, 1);
      double h = iHigh(_Symbol, PERIOD_M5, 1);
      double l = iLow(_Symbol, PERIOD_M5, 1);

      SavedUpperWick = h - MathMax(o, c);
      SavedLowerWick = MathMin(o, c) - l;

      //================ CANDLE C =================
      double oC = iOpen(_Symbol, PERIOD_M5, 2);
      double cC = iClose(_Symbol, PERIOD_M5, 2);
      double hC = iHigh(_Symbol, PERIOD_M5, 2);
      double lC = iLow(_Symbol, PERIOD_M5, 2);

      SavedCUpperWick = hC - MathMax(oC, cC);
      SavedCLowerWick = MathMin(oC, cC) - lC;

      SavedCandleBull = (c > o);
      SavedCandleBear = (c < o);

      SavedSpecialData = true;

      Print("SPECIAL CANDLE B & C SAVED");
      return;
   }
}

//================ PREPROCESS START =================

datetime candleOpen = SignalCandleTime;

if(!CrossDetected)
   return;

if(_Symbol != HAFSSignalSymbol)
   return;

//==================================================
// FINAL CALCULATION ALREADY DONE -> FREEZE PREPROCESS
//==================================================

if(FinalCalculationReady)
   return;

if(TimeCurrent() - candleOpen >= 290)
{
   if(!PreProcessStarted)
   {
      PreProcessStarted = true;
      Print("PREPROCESS STARTED");
   }

   //================ PREPROCESS =================

   CachedMarketType     = GetMarketType();
   CachedTrendDirection = GetTrendDirection();
   CachedTrendStrength  = GetTrendStrength();
   CachedVolatility     = GetVolatilityState();
   CachedBehavior       = GetMarketBehavior();

   // Update current values
   CurrentMarketType     = CachedMarketType;
   CurrentTrendDirection = CachedTrendDirection;
   CurrentTrendStrength  = CachedTrendStrength;
   CurrentVolatility     = CachedVolatility;
   CurrentBehavior       = CachedBehavior;

   // Cache Aegis Decision
   CachedAegisDecision = CalculateAegisDecision();
CachedMarketBias = GetMarketBias();
   // Cache Candle Strength
   //================ CACHE CANDLE STRENGTH =================

CachedCandleStrength = GetCandleStrength(0);

PrintFormat(
   "290 SEC -> CANDLE STRENGTH CACHED = %.2f%%",
   CachedCandleStrength
);
   //================ HAFS PREPROCESS =================

if(CrossSeenThisCandle &&
   CachedCandleStrength >= MinimumCandleStrengthPercent &&
   !CachedCaseDetected)
{
   CachedHAFSReady = true;

   

   // Cache B & C wick values
   CachedBBuyWick  = CandleBSupportsBuyWick();
   CachedBSellWick = CandleBSupportsSellWick();

   CachedCBuyWick  = CandleCSupportsBuyWick();
   CachedCSellWick = CandleCSupportsSellWick();
CachedCaseDetected = true;
  

   Print("HAFS CASE DETECTED & B/C WICKS CACHED");
  
}
}

//================ PREPROCESS END =================

//==================================================
// FINAL CALCULATION
// FIRST AVAILABLE TICK AT OR AFTER 298.000 SEC
//==================================================

MqlTick finalTick;

if(!SymbolInfoTick(_Symbol, finalTick))
   return;

long signalStartMs =
   (long)SignalCandleTime * 1000;

long currentServerMs =
   (long)finalTick.time_msc;

long candleAgeMs =
   currentServerMs - signalStartMs;

if(candleAgeMs >= 298000 &&
   CrossDetected &&
   !FinalCalculationReady)
{
   PrintFormat(
      "FINAL CALCULATION STARTED -> AGE=%I64d ms",
      candleAgeMs
   );

   //==================================================
   // FINAL SIGNAL CANDLE STRENGTH
   //==================================================

   CachedCandleStrength = GetCandleStrength(0);

   PrintFormat(
      "FINAL CANDLE STRENGTH -> %.2f%%",
      CachedCandleStrength
   );

   if(CachedCandleStrength < MinimumCandleStrengthPercent)
   {
      PrintFormat(
         "FINAL CALC -> CANDLE STRENGTH TOO LOW %.2f%%",
         CachedCandleStrength
      );

      FinalCalculationReady = true;
      ExecutionArmed = false;
      return;
   }

   //==================================================
   // FINAL A / SIGNAL WICK
   //==================================================

   double oA = iOpen(_Symbol, PERIOD_M5, 0);
   double cA = iClose(_Symbol, PERIOD_M5, 0);
   double hA = iHigh(_Symbol, PERIOD_M5, 0);
   double lA = iLow(_Symbol, PERIOD_M5, 0);

   CachedAUpperWick =
      hA - MathMax(oA, cA);

   CachedALowerWick =
      MathMin(oA, cA) - lA;

   double totalA =
      CachedAUpperWick + CachedALowerWick;

   double diffA =
      MathAbs(
         CachedAUpperWick -
         CachedALowerWick
      );

   double requiredA =
      totalA * WickDifferencePercent / 100.0;

   CachedAWickBuy =
      CachedALowerWick > CachedAUpperWick &&
      diffA >= requiredA;

   CachedAWickSell =
      CachedAUpperWick > CachedALowerWick &&
      diffA >= requiredA;

   PrintFormat(
      "A WICK FINAL @ %.3f SEC -> Upper=%.5f Lower=%.5f Buy=%s Sell=%s",
      candleAgeMs / 1000.0,
      CachedAUpperWick,
      CachedALowerWick,
      CachedAWickBuy ? "YES" : "NO",
      CachedAWickSell ? "YES" : "NO"
   );

   //==================================================
// FINAL HAFS CASE
//==================================================

DetectHAFSCase();

CurrentHAFSCase = CachedHAFSCase;

//==================================================
// CALCULATE + FREEZE FINAL DIRECTION AT 298 SEC
// NO TRADE YET
//==================================================

FinalDirection = 0;

FreezeOnlyMode = true;

ExecuteHAFSCase();

FreezeOnlyMode = false;

if(FinalDirection == 1)
{
   Print("298 SEC -> FINAL DIRECTION FROZEN: BUY");
}
else if(FinalDirection == -1)
{
   Print("298 SEC -> FINAL DIRECTION FROZEN: SELL");
}
else
{
   Print("298 SEC -> FINAL DIRECTION FREEZE FAILED");
   
   FinalCalculationReady = true;
   ExecutionArmed = false;
   return;
}

//==================================================
// FREEZE EVERYTHING
//==================================================

FinalCalculationReady = true;
ExecutionArmed = true;

//==================================================
// FINAL ORDER SEND TARGET = 299.000 SEC
// FINAL DIRECTION IS ALREADY FROZEN
//==================================================

long targetServerMs =
   signalStartMs + 299100;

long waitMs =
   targetServerMs - currentServerMs;

if(waitMs <= 0)
{
   PrintFormat(
      "FINAL ORDER TARGET ALREADY PASSED -> AGE=%.3f SEC",
      candleAgeMs / 1000.0
   );

   ExecutionArmed = false;
   FinalCalculationReady = false;
   return;
}

//==================================================
// STORE SERVER-TIME ORDER SEND TARGET
//==================================================

ExecutionTargetServerMs =
   targetServerMs;

PrintFormat(
   "FINAL ORDER TARGET SET -> SERVER AGE=299.100 SEC | WAIT=%I64d ms",
   waitMs
);

PrintFormat(
   "FINAL CALC DONE -> AGE=%.3f SEC",
   candleAgeMs / 1000.0
);

Print(
   "EXECUTION ARMED -> ORDER SEND TARGET 299.100 SEC"
);

return;
}
   // Allow new crossover only after MAs separate again


   //--- BASKET TAKE PROFIT
if(BasketDirection != 0)
{
   double liveBasketProfit = GetBasketProfit();

   if(liveBasketProfit >= BasketTP)
   {
      PrintFormat(
         "BASKET TP HIT >>> Profit=%.2f | Target=%.2f",
         liveBasketProfit,
         BasketTP
      );

      CloseAllTrades();
      ResetBasket();

      SignalAlreadyTraded = true;

      return;
   }
}
//================ EMERGENCY STOP LOSS (1 MIN DELAY)

if(!IsOneDollarMarket() &&
   BasketDirection != 0 &&
   TimeCurrent() - TradeOpenTime >= 60 &&
   profit <= -EmergencySL)
{
   Print("EMERGENCY SL HIT - $", profit);

   CloseAllTrades();
   ResetBasket();

   return;
}
 //--- BASKET STOP LOSS

if(!IsOneDollarMarket() &&
   BasketDirection != 0 &&
   HoldTimeFinished() &&
   profit <= -BasketSL)
{
   Print("BASKET SL HIT — $", profit);

   CloseAllTrades();
   ResetBasket();

   return;
}

//--- TRAILING STOP
//if(BasketDirection != 0)
//   CheckTrailing();

// Unlock only after MAs separate again
if(!AnyCross())
{
   SignalAlreadyTraded = false;
}

if(SignalAlreadyTraded)
   return;

if(!InSession())        return;

  

   //--- STEP 2: On the NEXT new candle after cross was detected — enter trade
 if(false && newBar && CrossDetected && BasketDirection == 0)
{
Print(">>> ENTERED MAIN TRADE LOGIC");
  

   // Cancel signal if it's older than one M5 candle
  if(TimeCurrent() - LastCrossTime > 300)
{
    Print("Cross expired");

    CrossDetected = false;
    CrossDirection = 0;

    return;
}

   // ...the rest of your existing code continues here...

// Cancel signal if it's older than one M5 candle

// Cancel stale signals
int trend = GetTrend();

if(CrossDirection == 1 && trend != 1)
{
   Print("BUY SIGNAL CANCELLED - Trend not bullish");
   Print("EXIT: Trend Filter");
   CrossDetected = false;
   CrossDirection = 0;
   return;
}

if(CrossDirection == -1 && trend != -1)
{
   Print("SELL SIGNAL CANCELLED - Trend not bearish");
   Print("EXIT: Trend Filter");
   CrossDetected = false;
   CrossDirection = 0;
   return;
}

if(false && (IsDoji() || OlderDoji()))
{
    Print("EXIT: Doji Filter");
    Print("TRADE CANCELLED - DOJI DETECTED");
    CrossDetected = false;
    CrossDirection = 0;
    return;
}





/*
// MA200 filter disabled for testing
if(MA200TooClose())
{
   Print("MA200 too close - Cancel signal");
   CrossDetected = false;
   CrossDirection = 0;
   return;
}
*/

// Cancel stale signals


if(newBar && CachedCaseDetected)
{
    CurrentHAFSCase = CachedHAFSCase;

    ExecuteHAFSCase();

    CrossDetected = false;
    CrossSeenThisCandle = false;
    SignalCandleTime = 0;

    return;
}

  if(CrossDirection == 1)
{
if(CachedCaseDetected)
   return;
if(LastTradeWasLoss)
{
   Print(">>> RECOVERY MODE ACTIVE");
}
   bool signalBull = OlderBullish();
   bool signalBear = OlderBearish();

   bool shift1Bull = ThirdBullish();
   bool shift1Bear = ThirdBearish();

   bool shift2Bull =
      iClose(_Symbol,PERIOD_M5,3) >
      iOpen(_Symbol,PERIOD_M5,3);

   bool shift2Bear =
      iClose(_Symbol,PERIOD_M5,3) <
      iOpen(_Symbol,PERIOD_M5,3);

   Print(
      "HAFS => ",
      " signalBull=",signalBull,
      " signalBear=",signalBear,
      " shift1Bull=",shift1Bull,
      " shift1Bear=",shift1Bear,
      " shift2Bull=",shift2Bull,
      " shift2Bear=",shift2Bear
   );
   //================ HAFS COMMON CALCULATIONS ================

bool WickBuy  = WickConfirmation(true);
bool WickSell = WickConfirmation(false);

bool BBuyWick  = CachedBBuyWick;
bool BSellWick = CachedBSellWick;

bool CBuyWick  = CachedCBuyWick;
bool CSellWick = CachedCSellWick;

//==========================================================
//================ BUY CASE 1 REVERSAL ================
if(shift1Bull && signalBull && shift2Bear)
{
CachedHAFSCase = BUY1_REV;
    Print("HAFS BUY CASE 1 REVERSAL");

   bool A = WickSell;
bool B = BSellWick;
bool C = CSellWick;

  


// ================ MINIMUM SIGNAL WICK SIZE FILTER ================

double TotalSignalWick = SignalUpperWick + SignalLowerWick;

if(TotalSignalWick < MinimumWickSize)
{
    PrintFormat("BUY1 REV: Signal wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalSignalWick,
                MinimumWickSize);
    return;
}

   // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("BUY1 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("BUY1 REV: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1 REV: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1 REV: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}

return;
}
//================ BUY CASE 1 ================
else if(shift1Bull && signalBull)
{
CachedHAFSCase = BUY1;
    Print("BUY CASE 1");


    bool A = WickBuy;
bool B = BBuyWick;
bool C = CBuyWick;


    
    // ================ MINIMUM WICK SIZE FILTER ================

double TotalWick = SignalUpperWick + SignalLowerWick;

if(TotalWick < MinimumWickSize)
{
    PrintFormat("BUY1: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalWick,
                MinimumWickSize);
    return;
}

   // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("BUY1: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY1: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("BUY1: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY1: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY1: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY1: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
//================ BUY CASE 2 ================
else if(shift1Bull && signalBear && shift2Bear)
{
CachedHAFSCase = BUY2;
   Print("HAFS BUY CASE 2");


   bool A = WickBuy;
   bool B = BBuyWick;
   bool C = CBuyWick;


   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY2: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }


  // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("BUY2: A✓ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY2: A✓ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY2: A✓ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY2: A✓ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("BUY2: A✗ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY2: A✗ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY2: A✗ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY2: A✗ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}

return;
}
//================ BUY CASE 5 ================
else if(shift1Bull && signalBear && shift2Bull)
{
CachedHAFSCase = BUY5;
   Print("HAFS BUY CASE 5");

   bool A = WickSell;
   bool B = BSellWick;
   bool C = CSellWick;

   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY5: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("BUY5: A✓ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY5: A✓ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY5: A✓ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY5: A✓ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("BUY5: A✗ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY5: A✗ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY5: A✗ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY5: A✗ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}

return;
}
//================ BUY CASE 3 ================
else if(shift1Bear && signalBull && shift2Bear)
{
CachedHAFSCase = BUY3;
   Print("HAFS BUY CASE 3");


   bool A = WickBuy;
   bool B = BBuyWick;
   bool C = CBuyWick;


   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY3: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }


 

   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("BUY3: A✓ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY3: A✓ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY3: A✓ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY3: A✓ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("BUY3: A✗ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY3: A✗ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY3: A✗ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("BUY3: A✗ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}

return;
}
//================ BUY CASE 6 ================
else if(shift1Bear && signalBull && shift2Bull)
{
CachedHAFSCase = BUY6;
   Print("HAFS BUY CASE 6");

   bool A = WickSell;
   bool B = BSellWick;
   bool C = CSellWick;

   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("BUY6: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }


  // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("BUY6: A✓ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY6: A✓ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY6: A✓ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY6: A✓ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("BUY6: A✗ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY6: A✗ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("BUY6: A✗ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("BUY6: A✗ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}

return;
}
//================ BUY CASE 4 REVERSAL ================
else if(shift1Bear && signalBear && shift2Bull)
{
CachedHAFSCase = BUY4_REV;
    Print("HAFS BUY CASE 4 REVERSAL");

   bool A = WickBuy;
bool B = BBuyWick;
bool C = CBuyWick;

    
    // ================ MINIMUM SIGNAL WICK SIZE FILTER ================

double TotalSignalWick = SignalUpperWick + SignalLowerWick;

if(TotalSignalWick < MinimumWickSize)
{
    PrintFormat("BUY4 REV: Signal wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalSignalWick,
                MinimumWickSize);
    return;
}

// ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("BUY4 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY4 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY4 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("BUY4 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("BUY4 REV: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4 REV: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY4 REV: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4 REV: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
//================ BUY CASE 4 ================
else if(shift1Bear && signalBear && shift2Bear)
{
CachedHAFSCase = BUY4;
    Print("BUY CASE 4");


 bool A = WickSell;
bool B = BSellWick;
bool C = CSellWick;


// ================ MINIMUM WICK SIZE FILTER ================

double TotalWick = SignalUpperWick + SignalLowerWick;

if(TotalWick < MinimumWickSize)
{
    PrintFormat("BUY4: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalWick,
                MinimumWickSize);
    return;
}


   // ================= BUY4 MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("BUY4: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY4: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("BUY4: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("BUY4: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("BUY4: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
else
{
   Print("HAFS BUY FAILED");
}


CrossDetected = false;
CrossDirection = 0;
}

else if(CrossDirection == -1)
{

   bool signalBull = OlderBullish();
   bool signalBear = OlderBearish();

   bool shift1Bull = ThirdBullish();
   bool shift1Bear = ThirdBearish();

   bool shift2Bull =
      iClose(_Symbol,PERIOD_M5,3) >
      iOpen(_Symbol,PERIOD_M5,3);

   bool shift2Bear =
      iClose(_Symbol,PERIOD_M5,3) <
      iOpen(_Symbol,PERIOD_M5,3);

   Print(
      "HAFS => ",
      " signalBull=",signalBull,
      " signalBear=",signalBear,
      " shift1Bull=",shift1Bull,
      " shift1Bear=",shift1Bear,
      " shift2Bull=",shift2Bull,
      " shift2Bear=",shift2Bear
   );
//================ HAFS COMMON CALCULATIONS ================

bool WickBuy  = WickConfirmation(true);
bool WickSell = WickConfirmation(false);

bool BBuyWick  = CandleBSupportsBuyWick();
bool BSellWick = CandleBSupportsSellWick();

bool CBuyWick  = CandleCSupportsBuyWick();
bool CSellWick = CandleCSupportsSellWick();

//==========================================================
//================ SELL CASE 1 ================
 if(shift1Bear && signalBear && shift2Bear)
{
CachedHAFSCase = SELL1;
    Print("SELL CASE 1");


   bool A = WickSell;
bool B = BSellWick;
bool C = CSellWick;

    // ================ MINIMUM WICK SIZE FILTER ================

double TotalWick = SignalUpperWick + SignalLowerWick;

if(TotalWick < MinimumWickSize)
{
    PrintFormat("SELL1: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalWick,
                MinimumWickSize);
    return;
}

   // ================= SELL1 MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("SELL1: A✓ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1: A✓ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL1: A✓ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1: A✓ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("SELL1: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL1: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
//================ SELL CASE 1 REVERSAL ================
else if(shift1Bear && signalBear && shift2Bull)
{
CachedHAFSCase = SELL1_REV;
    Print("HAFS SELL CASE 1 REVERSAL");

   bool A = WickBuy;
bool B = BBuyWick;
bool C = CBuyWick;

    
    // ================ MINIMUM SIGNAL WICK SIZE FILTER ================

double TotalSignalWick = SignalUpperWick + SignalLowerWick;

if(TotalSignalWick < MinimumWickSize)
{
    PrintFormat("SELL1 REV: Signal wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalSignalWick,
                MinimumWickSize);
    return;
}

    // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("SELL1 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL1 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL1 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL1 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("SELL1 REV: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1 REV: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL1 REV: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL1 REV: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
//================ SELL CASE 2 ================
else if(shift1Bull && signalBear && shift2Bull)
{
CachedHAFSCase = SELL2;
   Print("HAFS SELL CASE 2");


   bool A = WickSell;
   bool B = BSellWick;
   bool C = CSellWick;


   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL2: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

  

   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("SELL2: A✓ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL2: A✓ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL2: A✓ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL2: A✓ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("SELL2: A✗ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL2: A✗ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL2: A✗ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL2: A✗ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}

return;
}
//================ SELL CASE 5 ================
else if(shift1Bull && signalBear && shift2Bear)
{
CachedHAFSCase = SELL5;
   Print("HAFS SELL CASE 5");


   bool A = WickBuy;
   bool B = BBuyWick;
   bool C = CBuyWick;


   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL5: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }

  


   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("SELL5: A✓ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL5: A✓ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL5: A✓ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL5: A✓ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("SELL5: A✗ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL5: A✗ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL5: A✗ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL5: A✗ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}

return;
}
//================ SELL CASE 3 ================
else if(shift1Bear && signalBull && shift2Bull)
{
CachedHAFSCase = SELL3;
   Print("HAFS SELL CASE 3");

   bool A = WickSell;
   bool B = BSellWick;
   bool C = CSellWick;

   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL3: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }


   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("SELL3: A✓ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL3: A✓ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL3: A✓ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL3: A✓ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("SELL3: A✗ B✓ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL3: A✗ B✓ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL3: A✗ B✗ C✓ -> SELL");
         AegisFinalDecision(-1);
      }
      else
      {
         Print("SELL3: A✗ B✗ C✗ -> BUY");
         AegisFinalDecision(1);
      }
   }
}

return;
}
//================ SELL CASE 6 ================
else if(shift1Bear && signalBull && shift2Bear)
{
CachedHAFSCase = SELL6;
   Print("HAFS SELL CASE 6");


   bool A = WickBuy;
   bool B = BBuyWick;
   bool C = CBuyWick;


   // ================ MINIMUM WICK SIZE FILTER ================

   double TotalWick = SignalUpperWick + SignalLowerWick;

   if(TotalWick < MinimumWickSize)
   {
      PrintFormat("SELL6: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                  TotalWick,
                  MinimumWickSize);
      return;
   }




   // ================= PHOENIX MASTERMIND =================

if(A)
{
   if(B)
   {
      if(C)
      {
         Print("SELL6: A✓ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL6: A✓ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL6: A✓ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL6: A✓ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}
else
{
   if(B)
   {
      if(C)
      {
         Print("SELL6: A✗ B✓ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL6: A✗ B✓ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
   else
   {
      if(C)
      {
         Print("SELL6: A✗ B✗ C✓ -> BUY");
         AegisFinalDecision(1);
      }
      else
      {
         Print("SELL6: A✗ B✗ C✗ -> SELL");
         AegisFinalDecision(-1);
      }
   }
}

return;
}
//================ SELL CASE 4 REVERSAL ================
else if(shift1Bull && signalBull && shift2Bear)
{
CachedHAFSCase = SELL4_REV;
    Print("HAFS SELL CASE 4 REVERSAL");

    bool A = WickSell;
bool B = BSellWick;
bool C = CSellWick;

    
    // ================ MINIMUM SIGNAL WICK SIZE FILTER ================

double TotalSignalWick = SignalUpperWick + SignalLowerWick;

if(TotalSignalWick < MinimumWickSize)
{
    PrintFormat("SELL4 REV: Signal wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalSignalWick,
                MinimumWickSize);
    return;
}

    // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("SELL4 REV: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4 REV: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL4 REV: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4 REV: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("SELL4 REV: A✗ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4 REV: A✗ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL4 REV: A✗ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4 REV: A✗ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}

return;
}
//================ SELL CASE 4 ================
else if(shift1Bull && signalBull)
{
CachedHAFSCase = SELL4;
    Print("SELL CASE 4");


   bool A = WickBuy;
bool B = BBuyWick;
bool C = CBuyWick;

    // ================ MINIMUM WICK SIZE FILTER ================

double TotalWick = SignalUpperWick + SignalLowerWick;

if(TotalWick < MinimumWickSize)
{
    PrintFormat("SELL4: Wick too small -> TotalWick=%.2f Minimum=%.2f",
                TotalWick,
                MinimumWickSize);
    return;
}

   // ================= PHOENIX MASTERMIND =================

if(A)
{
    if(B)
    {
        if(C)
        {
            Print("SELL4: A✓ B✓ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4: A✓ B✓ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL4: A✓ B✗ C✓ -> BUY");
            AegisFinalDecision(1);
        }
        else
        {
            Print("SELL4: A✓ B✗ C✗ -> SELL");
            AegisFinalDecision(-1);
        }
    }
}
else
{
    if(B)
    {
        if(C)
        {
            Print("SELL4: A✗ B✓ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL4: A✗ B✓ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
    else
    {
        if(C)
        {
            Print("SELL4: A✗ B✗ C✓ -> SELL");
            AegisFinalDecision(-1);
        }
        else
        {
            Print("SELL4: A✗ B✗ C✗ -> BUY");
            AegisFinalDecision(1);
        }
    }
}

return;
}
if(CachedHAFSCase != CASE_NONE)
{
   CachedCaseDetected = true;
   Print("HAFS CASE CACHED = ", CachedHAFSCase);
}
else
{
   Print("HAFS NOT DETECTED");
}


CrossDetected = false;
CrossDirection = 0;
}
}
}