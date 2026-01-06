//+----------------------------------------------------------------------+
//|                                                            CTV.mq5   |
//|                                           Copyright 2026, AgSpades   |
//|                                                   https://mql5.com   |
//|                                                                      |
//+----------------------------------------------------------------------+
#property copyright "Copyright 2026, AgSpades"
#property link "https://github.com/agspades"
#property version "1.20"
#property description "Copy Signals From TradingView Relay Server via ZeroMQ with Low Latency"

#include <Trade/Trade.mqh>
#include <Zmq/Zmq.mqh>
#include <Json.mqh>

// Forward declarations for functions implemented later in the file
void manageTrailingStops();
bool checkTradingConditions();
bool validateTimeFormat(string timeStr);
bool isWithinTradingSession();
void checkNews(bool &retFlag);
bool isUpcomingNews();
void evaluateAndPlaceOrders();
void closeAllOrders();
void closeAllPositions();
bool safePositionClose(ulong ticket, int maxRetries = 3);
double normalizeVolume(double volume);
double adjustLotForMargin(double desiredLot, ENUM_ORDER_TYPE orderType, double orderPrice);
bool CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type);
bool CheckMoneyForPendingOrder(string symb, double lots, ENUM_ORDER_TYPE type, double orderPrice);
bool wasTradeOnCurrentCandle(string symbol);

// ZeroMQ Signal Receiver Functions
bool InitializeZMQ();
void CheckForSignals();
void ProcessJSONSignal(string jsonString);
string MapSymbol(string transmitterSymbol);
void LoadManualSymbolMappings();

// Volume Filter Functions
void initVolumeFilter();
bool validateTradeWithVolume(bool isBuy);
void manageVolumeBasedExits();

// Candle Open Filter Functions
bool validateTradeWithCandleOpen(bool isBuy);
void manageCandleOpenBasedExits();

/////////////////////////////Enums///////////////////////////

enum SEPARATOR_DROPDOWN
{
   SEPARATOR_COMMA = 0,    // Comma
   SEPARATOR_SEMICOLON = 1 // Semicolon
};

enum LotType
{
   Fixed_Lots = 0,      // Fixed Lots
   Pct_Balance = 1,     // Percentage of Balance
   Pct_Equity = 2,      // Percentage of Equity
   Pct_Free_Margin = 3, // Percentage of Free Margin
   Proportional_Lot = 4 // Proportional to Balance
};

enum SystemType
{
   SYS_FOREX = 0, // Point-based (Forex)
   SYS_GOLD = 1   // Percentage-based (Gold/Indices)
};

///////////////////////////////////////////////////////////

/////////////////////////Inputs///////////////////////////////
input bool InpEnableTrading = true; // Enable Trading By EA

input group "=== Signal Receiver Settings ===" 
string InpProtocol = "tcp://"; // Protocol
input string InpIPAddress = "127.0.0.1";                                      // Server IP address
input string InpPort = "9090";                                                // Server port number
input bool InpEnableLogging = true;                                           // Enable detailed logging
input bool InpShowLatencyStats = false;                                       // Show signal processing latency
int InpReceiverTimerMs = 1;                                                   // Receiver timer interval in milliseconds (1ms = fastest)

input group "=== Symbol Mapping Settings ==="
input bool InpEnableSymbolMapping = true; // Enable automatic symbol mapping
input bool InpAutoHandleSuffixes = true;                                                // Automatically handle common suffixes
input string InpManualSymbolMaps = "";                                                  // Manual mappings: "XAUUSD,GOLD;EURUSD,EUR.USD"
input string InpReceiverSuffix = "";                                                    // Add suffix to all symbols (e.g., ".c" or ".raw")

input group "=== Trading Profile Settings ===" 
input SystemType InpSystemType = SYS_GOLD; // Trading system profile
input LotType InpLotType = Proportional_Lot;                                              // Type of LotSize
input double InpFixedLots = 0.01;                                                         // Fixed lot size
input double InpRiskPercent = 1;                                                          // Risk as percentage(if selected)
input double InpBaseBalance = 100;                                                        // Base balance for proportional lots
input group "Trading Session (Server Time)"
    // time settings
    input bool InpUseTradingSession = false;    // Enable trading session window
input string InpSessionStart = "02:00:00";     // Session start time (HH:MM:SS)
input string InpSessionEnd = "20:30:00";       // Session end time (HH:MM:SS)
input bool InpManageTradesOutsideHours = true; // Manage open trades outside hours
input int InpMagicNumber = 161225;             // Magic number
input string InpComment = "CTV v1";            // Order comment

input group "=== Take Profit Settings ===" 
input double InpTPAsPercentage = 0.5; // Take Profit % (Gold/Percentage mode)
input int InpTPPoints = 300;                                                     // Take Profit in points (Forex mode)

input group "=== Stop Loss Settings ===" 
input double InpSLAsPercentage = 0.25; // Stop Loss % (Gold/Percentage mode)
input int InpSLPoints = 150;                                                    // Stop Loss in points (Forex mode)

input group "=== Trailing Stop Settings ==="
    // Trailing SL Settings
    input bool InpEnableTrailing = true;      // Enable Trailing Stop
input double InpTSLTriggerAsPercentage = 2.0; // TSL Trigger % of TP distance (Gold mode)
input double InpTSLStepAsPercentage = 1.0;    // TSL Step % of TP distance (Gold mode)
input int InpTSLTriggerPoints = 150;          // TSL Trigger in points (Forex mode)
input int InpTSLStepPoints = 100;             // TSL Step in points (Forex mode)

input group "=== Order Management ===" 
input bool InpMaxOneTrade = false; // Allow only one trade at a time
input bool InpMaxOneTradePerCandle = true;                               // Allow only one trade per candle
input int InpMaxSpread = 50;                                             // Maximum acceptable spread in points

input group "=== News Filter ==="
    // News Filter Parameters
    input bool InpFilterNews = false;                                                      // Enable news filter
input SEPARATOR_DROPDOWN InpNewsSeparator = SEPARATOR_COMMA;                               // Separator for news filtering
input string InpKeyNews = "BCB,NFP,JOLTS,Nonfarm,PMI,Retail,GDP,Confidence,Interest Rate"; // Key news events
input string InpNewsCurrency = "USD";                                                      // Currencies to filter news by
input int InpDaysNewsLookup = 100;                                                         // Number of days to look back for news events
input int InpStopBeforeMinutes = 60;                                                       // Stop trading X minutes before high-impact news
input int InpStartAfterMinutes = 60;                                                       // Start trading X minutes after high-impact news

input group "=== SAR Filter Settings ===" input bool InpUseSARFilter = true; // Enable SAR Filter
input double InpSARStep = 0.02;                                              // SAR Step
input double InpSARMaximum = 0.2;                                            // SAR Maximum

input group "=== Volume Filter Settings ===" input bool InpUseVolumeFilter = false; // Enable Volume Entry Filter
input bool InpUseVolumeExitMonitor = false;                                         // Enable Volume Exit Monitor
input ENUM_APPLIED_VOLUME InpVolumeType = VOLUME_TICK;                              // Volume Type

input group "=== Candle Open Filter Settings ===" input bool InpUseCandleOpenFilter = true; // Enable Candle Open Entry Filter
input bool InpUseCandleOpenExitMonitor = true;                                              // Enable Candle Open Exit Monitor

input group "Aesthetics"
    // Aesthetics
    input bool InpShowGrid = false;            // Display Grid on the Chart
input color InpChartColorTradingOff = clrPink; // Chart color when trading is off
input color InpChartColorTradingOn = clrBlack; // Chart color when trading is on

///////////////////////////////////////////////////////////
//////////////////////Global Variables//////////////////////////
// Global Objects
CTrade g_trade; // Trade object for order management
CPositionInfo g_pos;
COrderInfo g_order;

bool g_trailingDisabled = false;                                    // Flag to disable trailing stops
int g_expirationBars = 50;                                          // Order expiration in bars
double g_riskPercent = InpRiskPercent;                              // Risk percentage
bool g_isTradingActive = true;                                      // Flag to track if trading is active
bool g_tradingAllowed = true;                                       // Flag to control if trading is allowed
double g_TPPoints, g_SLPoints, g_TSLTriggerPoints, g_TSLStepPoints; // Trade parameters in points
bool g_showIndicators = true;                                       // Show indicators during backtesting (slower but visual)
datetime g_timestamp = 0;                                           // Timestamp for the last processed bar

// Indicator Handles - Add your indicators here
// int g_handleIndicator = INVALID_HANDLE;

string g_TradingEnabledText = "";
bool g_TradingDisabledByNews = false; // Flag to track if trading is disabled by news
ushort g_sepCode;                     // Separator code for news filtering
string g_NewsToAvoid[];               // News events to avoid
datetime g_lastAvoidedNewsTime;

// ZeroMQ Variables
Context *g_context = NULL;  // ZMQ context
Socket *g_zmqSocket = NULL; // ZMQ socket (PULL)
string g_zmqEndpoint = "";  // Full endpoint string

// Symbol mapping storage
struct SymbolMapEntry
{
   string transmitterSymbol;
   string receiverSymbol;
};
SymbolMapEntry g_manualSymbolMaps[];
int g_manualMapCount = 0;

//---------------------- SAR Filter Variables ----------------------
int g_sarHandle = INVALID_HANDLE; // SAR indicator handle
double g_sarBuffer[];             // SAR values buffer

//---------------------- Volume Filter Variables ----------------------
int g_volumeHandle = INVALID_HANDLE; // Volume indicator handle
double g_volumeBuffer[];             // Volume values buffer
double g_volumeColorBuffer[];        // Volume color buffer (0=green, 1=red)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //---
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   updateDynamicParameters();
   ChartSetInteger(0, CHART_SHOW_GRID, InpShowGrid);

   // Validate trading session inputs if enabled
   if (InpUseTradingSession)
   {
      if (!validateTimeFormat(InpSessionStart))
      {
         Print("ERROR: Invalid Session Start time format. Expected HH:MM:SS, got: ", InpSessionStart);
         return (INIT_PARAMETERS_INCORRECT);
      }
      if (!validateTimeFormat(InpSessionEnd))
      {
         Print("ERROR: Invalid Session End time format. Expected HH:MM:SS, got: ", InpSessionEnd);
         return (INIT_PARAMETERS_INCORRECT);
      }
   }

   if (g_showIndicators)
   {
      TesterHideIndicators(false);
   }
   else
   {
      TesterHideIndicators(true);
   }

   // Initialize ZeroMQ receiver
   if (!InitializeZMQ())
   {
      Print("Failed to initialize ZeroMQ. EA will not function.");
      return (INIT_FAILED);
   }

   // Load manual symbol mappings
   LoadManualSymbolMappings();

   // Initialize SAR indicator if filter is enabled
   if (InpUseSARFilter)
   {
      g_sarHandle = iSAR(_Symbol, _Period, InpSARStep, InpSARMaximum);
      if (g_sarHandle == INVALID_HANDLE)
      {
         Print("Failed to create SAR indicator handle. Error: ", GetLastError());
         return (INIT_FAILED);
      }
      ArraySetAsSeries(g_sarBuffer, true);
   }

   // Initialize Volume indicator if filter is enabled
   if (InpUseVolumeFilter || InpUseVolumeExitMonitor)
   {
      initVolumeFilter();
   }

   // Setup high-frequency timer for signal checking (1ms = fastest possible)
   EventSetMillisecondTimer(InpReceiverTimerMs);
   Print("Signal receiver timer set to ", InpReceiverTimerMs, "ms interval");

   if (InpLotType == Fixed_Lots)
   {
      double normalizedLots = normalizeVolume(InpFixedLots);
   }

   Print("=== CTV Signal Receiver Initialized ===");
   Print("Listening on: ", g_zmqEndpoint);
   Print("Symbol mapping: ", InpEnableSymbolMapping ? "Enabled" : "Disabled");
   //---
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //---
   // Kill timer
   EventKillTimer();

   // Cleanup ZeroMQ
   if (g_zmqSocket != NULL)
   {
      g_zmqSocket.disconnect(g_zmqEndpoint);
      g_zmqSocket.unbind(g_zmqEndpoint);
      delete g_zmqSocket;
      g_zmqSocket = NULL;
   }

   if (g_context != NULL)
   {
      delete g_context;
      g_context = NULL;
   }

   // Release SAR handle
   if (g_sarHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_sarHandle);
      g_sarHandle = INVALID_HANDLE;
   }

   // Release Volume handle
   if (g_volumeHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_volumeHandle);
      g_volumeHandle = INVALID_HANDLE;
   }

   if (reason == REASON_REMOVE || reason == REASON_RECOMPILE)
   {
      ChartSetInteger(0, CHART_SHOW_GRID, true); // Restore grid on removal
   }
   // remove placed orders and close positions
   closeAllOrders();
   closeAllPositions();

   Print("=== CTV Signal Receiver Stopped ===");
   //---
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!InpEnableTrading)
      return;
   //---
   // Update dynamic parameters on each tick for percentage-based systems
   if (InpSystemType == SYS_GOLD)
      updateDynamicParameters();

   if (InpEnableTrailing)
      manageTrailingStops();

   // Manage volume-based exits if enabled
   if (InpUseVolumeExitMonitor)
      manageVolumeBasedExits();

   // Manage candle open-based exits if enabled
   if (InpUseCandleOpenExitMonitor)
      manageCandleOpenBasedExits();

   bool retFlag;
   checkNews(retFlag);
   if (retFlag)
      return;
   g_isTradingActive = true;
   if (g_TradingEnabledText != "")
   {
      g_TradingEnabledText = "";
   }

   // Check trading session window
   if (InpUseTradingSession)
   {
      if (!isWithinTradingSession())
      {
         g_isTradingActive = false;
         ChartSetInteger(0, CHART_COLOR_BACKGROUND, InpChartColorTradingOff);
         if (!InpManageTradesOutsideHours)
            closeAllOrders();
         Comment("Outside trading session");
         return;
      }
   }

   ChartSetInteger(0, CHART_COLOR_BACKGROUND, InpChartColorTradingOn);

   if (!checkTradingConditions())
   {
      Comment("Trading conditions not suitable");
      return;
   }

   // Signal processing is handled by OnTimer() - this is just for trailing stops
   Comment("CTV Signal Receiver Active - Waiting for signals...");
}

void checkNews(bool &retFlag)
{
   retFlag = true;
   if (isUpcomingNews())
   {
      closeAllOrders();
      g_isTradingActive = false;
      ChartSetInteger(0, CHART_COLOR_BACKGROUND, InpChartColorTradingOff);
      g_TradingEnabledText = "Printed";
      return;
   }
   retFlag = false;
}

//+------------------------------------------------------------------+
void updateDynamicParameters()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (InpSystemType == SYS_GOLD)
   {
      // Percentage-based calculations for Gold/Indices
      g_TPPoints = (currentPrice * InpTPAsPercentage / 100.0) / point;
      g_SLPoints = (currentPrice * InpSLAsPercentage / 100.0) / point;

      // Trailing stop parameters as percentage of TP distance
      g_TSLTriggerPoints = g_TPPoints * (InpTSLTriggerAsPercentage / 100.0);
      g_TSLStepPoints = g_TPPoints * (InpTSLStepAsPercentage / 100.0);
   }
   else
   {
      // Point-based calculations for Forex
      g_TPPoints = InpTPPoints;
      g_SLPoints = InpSLPoints;
      g_TSLTriggerPoints = InpTSLTriggerPoints;
      g_TSLStepPoints = InpTSLStepPoints;
   }
}

double normalizeVolume(double volume)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if (volume < minVolume)
   {
      return minVolume;
   }

   if (maxVolume > 0 && volume > maxVolume)
   {
      return maxVolume;
   }

   // Normalize to step size
   volume = MathRound(volume / volumeStep) * volumeStep;
   volume = NormalizeDouble(volume, 2);

   // Final validation
   if (volume < minVolume)
      volume = minVolume;
   if (maxVolume > 0 && volume > maxVolume)
      volume = maxVolume;

   return volume;
}

bool checkTradingConditions()
{
   // Check if symbol is available for trading
   if (!SymbolInfoInteger(_Symbol, SYMBOL_SELECT))
   {
      return false;
   }

   // Check market session
   if (!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      return false;
   }

   // Check spread conditions
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if (spread > InpMaxSpread)
   {
      return false;
   }

   // Check account trading permissions
   if (!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      return false;
   }

   if (!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      return false;
   }

   // Check if there are enough bars for calculations
   int bars = Bars(_Symbol, _Period);
   int requiredBars = 45; // Adjust based on your indicator requirements
   if (bars < requiredBars)
   {
      return false;
   }

   // Check quote history availability and indicator readiness
   if (!checkHistoryAvailability())
   {
      return false;
   }

   // Check pending orders limit
   long maxOrders = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if (maxOrders > 0) // 0 means no limit
   {
      int currentOrders = OrdersTotal();
      if (currentOrders >= maxOrders)
      {
         return false;
      }
   }

   // Check symbol volume limits
   double positionVolume = getPositionVolume(_Symbol);
   double pendingVolume = getPendingOrdersVolume(_Symbol);
   double maxSymbolVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   if (maxSymbolVolume > 0) // 0 means no limit
   {
      double totalSymbolVolume = positionVolume + pendingVolume;
      if (totalSymbolVolume >= maxSymbolVolume)
      {
         return false;
      }
   }

   // Check margin requirements using OrderCalcMargin
   double testVolume = (InpLotType == Fixed_Lots) ? InpFixedLots : SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double requiredMargin = 0;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, testVolume, currentPrice, requiredMargin))
   {
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if (freeMargin < requiredMargin * 2) // Require 2x margin as safety buffer
   {
      return false;
   }

   // Check connection status
   if (!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      return false;
   }

   return true;
}

bool checkHistoryAvailability()
{
   int availableBars = Bars(_Symbol, _Period);
   int requiredBars = 10; // Buffer for calculations

   if (availableBars < requiredBars)
   {
      return false;
   }

   // Check if we can access indicator data
   // Add your indicator handle checks here
   // if (g_handleIndicator == INVALID_HANDLE)
   // {
   //    return false;
   // }

   // Try to copy a small amount of data to verify indicators are ready
   // double testBuffer[];
   // if (CopyBuffer(g_handleIndicator, 0, 1, 1, testBuffer) <= 0)
   // {
   //    return false;
   // }

   return true;
}

double getPositionVolume(string symbol)
{
   if (PositionSelect(symbol))
   {
      return PositionGetDouble(POSITION_VOLUME);
   }
   return 0.0; // No position exists
}

double getPendingOrdersVolume(string symbol)
{
   double totalVolume = 0.0;

   for (int i = 0; i < OrdersTotal(); i++)
   {
      if (OrderSelect(OrderGetTicket(i)))
      {
         if (OrderGetString(ORDER_SYMBOL) == symbol)
         {
            totalVolume += OrderGetDouble(ORDER_VOLUME_INITIAL);
         }
      }
   }

   return totalVolume;
}

void manageTrailingStops()
{
   if (g_trailingDisabled)
   {
      return; // Skip if trailing is disabled
   }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_pos.SelectByIndex(i))
         continue;
      if (g_pos.Symbol() != _Symbol || g_pos.Magic() != InpMagicNumber)
         continue;
      double takeProfit = g_pos.TakeProfit();
      double stopLossCurrent = g_pos.StopLoss();
      double currentPrice = (g_pos.PositionType() == POSITION_TYPE_BUY) ? bid : ask;

      if (g_pos.PositionType() == POSITION_TYPE_BUY)
      {
         if (bid - g_pos.PriceOpen() > g_TSLTriggerPoints * _Point)
         {
            double newSL = bid - g_TSLStepPoints * _Point;
            newSL = NormalizeDouble(newSL, _Digits);

            // Validate the new stop loss - must move forward (upward) only
            // For BUY: new SL must be HIGHER than current SL (or current SL is 0)
            if (stopLossCurrent == 0.0 || newSL > stopLossCurrent)
            {
               // Additional safety: ensure new SL is below current bid price
               if (newSL < bid)
               {
                  // Use safe modification with retry logic
                  if (safePositionModify(g_pos.Ticket(), newSL, takeProfit))
                  {
                     // Trailing stop updated successfully (reduced logging)
                  }
               }
            }
         }
      }
      else if (g_pos.PositionType() == POSITION_TYPE_SELL)
      {
         if (g_pos.PriceOpen() - ask > g_TSLTriggerPoints * _Point)
         {
            double newSL = ask + g_TSLStepPoints * _Point;
            newSL = NormalizeDouble(newSL, _Digits);

            // Validate the new stop loss - must move forward (downward) only
            // For SELL: new SL must be LOWER than current SL (or current SL is 0)
            if (stopLossCurrent == 0.0 || newSL < stopLossCurrent)
            {
               // Additional safety: ensure new SL is above current ask price
               if (newSL > ask)
               {
                  // Use safe modification with retry logic
                  if (safePositionModify(g_pos.Ticket(), newSL, takeProfit))
                  {
                     // Trailing stop updated successfully (reduced logging)
                  }
               }
            }
         }
      }
   }
}

bool safePositionModify(ulong ticket, double stopLoss, double takeProfit, int maxRetries = 3)
{
   if (!PositionSelectByTicket(ticket))
   {
      Print("Position #", ticket, " not found for modification");
      return false;
   }

   // --- Get current position info FIRST ---
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // --- Step 1: Validate and normalize the INCOMING stop levels immediately ---
   double validatedSL = stopLoss;
   double validatedTP = takeProfit;
   validateStopLevels(currentPrice, validatedSL, validatedTP, orderType);

   // --- Step 1.5: CRITICAL - Ensure trailing stop never moves backward ---
   // This prevents any validation adjustments from causing backward movement
   if (currentSL > 0.0 && validatedSL > 0.0)
   {
      if (posType == POSITION_TYPE_BUY)
      {
         // For BUY: SL should only move UP (increase), never DOWN
         if (validatedSL < currentSL)
         {
            validatedSL = currentSL; // Keep current SL instead of moving backward
         }
      }
      else if (posType == POSITION_TYPE_SELL)
      {
         // For SELL: SL should only move DOWN (decrease), never UP
         if (validatedSL > currentSL)
         {
            validatedSL = currentSL; // Keep current SL instead of moving backward
         }
      }
   }

   // --- Step 2: Perform a ROBUST check to see if modification is actually needed ---
   // This is the key fix: Compare after normalization. We use _Point as a tolerance.
   if (MathAbs(currentSL - validatedSL) < _Point && MathAbs(currentTP - validatedTP) < _Point)
   {
      // Print("No meaningful modification needed for position #", ticket);
      return true; // Success, as no change was required.
   }

   // --- Step 3: Check freeze level (no change from original logic) ---
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   if (freezeLevel > 0)
   {
      double marketPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if (MathAbs(marketPrice - currentPrice) < (freezeLevel * _Point))
      {
         return false;
      }
   }

   // --- Step 4: Attempt modification with retries (using the already validated levels) ---
   for (int retry = 0; retry < maxRetries; retry++)
   {
      if (g_trade.PositionModify(ticket, validatedSL, validatedTP))
      {
         return true;
      }

      uint lastError = GetLastError();
      // (The switch statement for handling errors remains the same as your original code)
      switch (lastError)
      {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
         Sleep(100); // Wait 100ms before retry
         break;
      case TRADE_RETCODE_FROZEN:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_MARKET_CLOSED:
         return false; // Don't retry these errors
      default:
         Sleep(200); // Wait 200ms before retry
         break;
      }
   }

   return false;
}

bool validateStopLevels(double orderPrice, double &stopLoss, double &takeProfit, ENUM_ORDER_TYPE orderType)
{
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP ||
                      orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP_LIMIT);

   long minStopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // If broker doesn't specify a stop level, use a safe default of 10 points
   if (minStopLevelPoints == 0)
   {
      minStopLevelPoints = 10;
   }

   double minStopDistance = minStopLevelPoints * _Point;

   // Normalize stop loss
   if (stopLoss > 0)
   {
      if (isBuyOrder)
      {
         // For a buy order, SL must be BELOW the order price
         if (stopLoss >= orderPrice)
            stopLoss = orderPrice - minStopDistance;
         // Check if the distance is sufficient
         if (orderPrice - stopLoss < minStopDistance)
            stopLoss = orderPrice - minStopDistance;
      }
      else // Sell Order
      {
         // For a sell order, SL must be ABOVE the order price
         if (stopLoss <= orderPrice)
            stopLoss = orderPrice + minStopDistance;
         // Check if the distance is sufficient
         if (stopLoss - orderPrice < minStopDistance)
            stopLoss = orderPrice + minStopDistance;
      }

      stopLoss = NormalizeDouble(stopLoss, _Digits);
   }

   // Normalize take profit
   if (takeProfit > 0)
   {
      double originalTP = takeProfit;

      if (isBuyOrder)
      {
         // For a buy order, TP must be ABOVE the order price
         if (takeProfit <= orderPrice)
            takeProfit = orderPrice + minStopDistance;
         // Check if the distance is sufficient
         if (takeProfit - orderPrice < minStopDistance)
            takeProfit = orderPrice + minStopDistance;
      }
      else // Sell Order
      {
         // For a sell order, TP must be BELOW the order price
         if (takeProfit >= orderPrice)
            takeProfit = orderPrice - minStopDistance;
         // Check if the distance is sufficient
         if (orderPrice - takeProfit < minStopDistance)
            takeProfit = orderPrice - minStopDistance;
      }

      takeProfit = NormalizeDouble(takeProfit, _Digits);
   }

   return true;
}

double normalizeStopLevel(double price, double stopLevel, bool isBuy, bool isStopLoss)
{
   if (stopLevel <= 0)
      return 0; // No stop level

   double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   // If no minimum stop level is specified by broker, use a reasonable default
   if (minStopLevel == 0)
      minStopLevel = 10 * _Point; // 10 points minimum

   double distance = MathAbs(stopLevel - price);

   if (distance < minStopLevel)
   {
      // Adjust stop level to meet minimum distance
      if (isBuy)
      {
         if (isStopLoss)
            stopLevel = price - minStopLevel; // SL below price for buy
         else
            stopLevel = price + minStopLevel; // TP above price for buy
      }
      else
      {
         if (isStopLoss)
            stopLevel = price + minStopLevel; // SL above price for sell
         else
            stopLevel = price - minStopLevel; // TP below price for sell
      }
   }

   return NormalizeDouble(stopLevel, _Digits);
}

void closeAllOrders()
{
   for (int i = OrdersTotal() - 1; i >= 0; --i)
   {
      if (!g_order.SelectByIndex(i))
         continue;
      if (g_order.Symbol() == _Symbol && g_order.Magic() == InpMagicNumber)
      {
         ulong orderTicket = g_order.Ticket();
         safeOrderDelete(orderTicket); // Use safe deletion method
      }
   }
}

bool safeOrderDelete(ulong ticket, int maxRetries = 3)
{
   if (!OrderSelect(ticket))
   {
      return false; // Order may have been executed or already deleted
   }

   // Get order information
   string orderSymbol = OrderGetString(ORDER_SYMBOL);
   ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   double orderSL = OrderGetDouble(ORDER_SL);
   double orderTP = OrderGetDouble(ORDER_TP);

   // Check if it's our order and symbol
   if (orderSymbol != _Symbol)
   {
      return false;
   }

   // Get current market prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   // Check freeze level for order cancellation
   if (freezeLevel > 0)
   {
      double freezeDistance = freezeLevel * _Point;
      double marketPrice = (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_BUY_LIMIT) ? ask : bid;

      if (MathAbs(orderPrice - marketPrice) < freezeDistance)
      {
         return false;
      }
   }

   // If the order has invalid stops, try to modify it first to fix the stops, then delete
   bool needsStopFix = false;

   // Attempt deletion with retries
   for (int retry = 0; retry < maxRetries; retry++)
   {
      if (g_trade.OrderDelete(ticket))
      {
         return true;
      }

      uint lastError = GetLastError();

      switch (lastError)
      {
      case TRADE_RETCODE_INVALID_STOPS:
         if (!needsStopFix) // Only try this once
         {
            needsStopFix = true;

            // Try to modify the order with valid stops first
            double validSL = orderSL;
            double validTP = orderTP;

            if (validateStopLevels(orderPrice, validSL, validTP, orderType))
            {
               if (g_trade.OrderModify(ticket, orderPrice, validSL, validTP, ORDER_TIME_GTC, 0))
               {
                  Sleep(100);
                  continue; // Try deletion again with fixed stops
               }
            }
            else
            {
               // If we can't fix stops, try to modify order without stops
               if (g_trade.OrderModify(ticket, orderPrice, 0, 0, ORDER_TIME_GTC, 0))
               {
                  Sleep(100);
                  continue; // Try deletion again without stops
               }
            }
         }
         break;

      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
         Sleep(100);
         break;

      case TRADE_RETCODE_FROZEN:
         return false; // Don't retry freeze level errors

      case TRADE_RETCODE_MARKET_CLOSED:
         return false;

      case TRADE_RETCODE_NO_CHANGES:
         return true; // Consider this a success

      default:
         Sleep(200);
         break;
      }

      // Refresh order info for next retry
      if (!OrderSelect(ticket))
      {
         return true; // Order doesn't exist anymore, consider success
      }
   }

   return false;
}

void closeAllPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if (!g_pos.SelectByIndex(i))
         continue;
      if (g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
      {
         ulong positionTicket = g_pos.Ticket();
         safePositionClose(positionTicket); // Use safe close method
      }
   }
}

bool safePositionClose(ulong ticket, int maxRetries = 3)
{
   if (!PositionSelectByTicket(ticket))
   {
      return false; // Position may have been closed already
   }

   // Get position information
   string posSymbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double posVolume = PositionGetDouble(POSITION_VOLUME);

   // Check if it's our position and symbol
   if (posSymbol != _Symbol)
   {
      return false;
   }

   // Check if we have enough money to close the position
   // Closing a BUY position requires a SELL order, and vice versa
   ENUM_ORDER_TYPE closeOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if (!CheckMoneyForTrade(posSymbol, posVolume, closeOrderType))
   {
      Print("Insufficient margin to close position #", ticket);
      return false;
   }

   // Attempt closure with retries
   for (int retry = 0; retry < maxRetries; retry++)
   {
      if (g_trade.PositionClose(ticket))
      {
         return true;
      }

      uint lastError = GetLastError();

      switch (lastError)
      {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
         Sleep(100);
         break;

      case TRADE_RETCODE_FROZEN:
         return false; // Don't retry freeze level errors

      case TRADE_RETCODE_MARKET_CLOSED:
         return false;

      case TRADE_RETCODE_NO_CHANGES:
         return true; // Consider this a success

      default:
         Sleep(200);
         break;
      }

      // Refresh position info for next retry
      if (!PositionSelectByTicket(ticket))
      {
         return true; // Position doesn't exist anymore, consider success
      }
   }

   return false;
}

bool isUpcomingNews()
{
   if (!InpFilterNews)
      return false;

   if (g_TradingDisabledByNews && TimeCurrent() - g_lastAvoidedNewsTime < InpStartAfterMinutes * 60)
      return true;

   string sep = (InpNewsSeparator == SEPARATOR_COMMA) ? "," : ";";
   g_sepCode = StringGetCharacter(sep, 0);
   int key = StringSplit(InpKeyNews, g_sepCode, g_NewsToAvoid);

   MqlCalendarValue values[];
   datetime startTime = TimeCurrent();
   datetime endTime = startTime + InpDaysNewsLookup * PeriodSeconds(PERIOD_D1);

   if (!CalendarValueHistory(values, startTime, endTime, NULL, NULL))
      return false;

   for (int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent event;
      if (!CalendarEventById(values[i].event_id, event))
         continue;

      MqlCalendarCountry country;
      if (!CalendarCountryById(event.country_id, country))
         continue;

      if (StringFind(InpNewsCurrency, country.currency) < 0)
         continue;

      for (int j = 0; j < key; j++)
      {
         string currentEvent = g_NewsToAvoid[j];
         if (StringFind(event.name, currentEvent) < 0)
            continue;

         Comment("Next News: ", country.currency, ": ", event.name, " -> ", values[i].time);
         if (values[i].time - TimeCurrent() < InpStopBeforeMinutes * 60)
         {
            g_TradingDisabledByNews = true;
            g_lastAvoidedNewsTime = values[i].time;
            if (g_TradingEnabledText == "" || g_TradingEnabledText != "Printed")
            {
               g_TradingEnabledText = "Trading disabled due to upcoming news: " + event.name + " at " + TimeToString(values[i].time, TIME_DATE | TIME_MINUTES);
               Comment(g_TradingEnabledText);
            }
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Main Trading Logic - IMPLEMENT YOUR STRATEGY HERE                |
//+------------------------------------------------------------------+
void evaluateAndPlaceOrders()
{
   // @todo Implement your trading logic here
   // This function should:
   // 1. Get indicator values
   // 2. Analyze market conditions
   // 3. Determine entry/exit signals
   // 4. Place orders using g_trade object

   // Example structure:
   // double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   // double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get indicator values
   // double indicatorBuffer[];
   // ArraySetAsSeries(indicatorBuffer, true);
   // if (CopyBuffer(g_handleIndicator, 0, 0, 10, indicatorBuffer) < 10)
   // {
   //    Comment("Insufficient Indicator data");
   //    return;
   // }

   // Check for existing positions
   int ourPositions = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_pos.SelectByIndex(i))
         continue;
      if (g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
         ourPositions++;
   }

   // Skip if we already have a position
   if (ourPositions > 0)
      return;

   // Calculate lot size
   double lotSize = calculateLotSize(g_SLPoints * _Point, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   lotSize = normalizeVolume(lotSize);

   if (lotSize <= 0.0)
      return;

   // TODO: Add your entry conditions here
   // bool buySignal = ...;
   // bool sellSignal = ...;

   // Example order placement:
   // if (buySignal)
   // {
   //    double entryPrice = ask;
   //    double sl = entryPrice - g_SLPoints * _Point;
   //    double tp = entryPrice + g_TPPoints * _Point;
   //    validateStopLevels(entryPrice, sl, tp, ORDER_TYPE_BUY);
   //
   //    double adjustedLot = adjustLotForMargin(lotSize, ORDER_TYPE_BUY, entryPrice);
   //    if (adjustedLot > 0 && CheckMoneyForTrade(_Symbol, adjustedLot, ORDER_TYPE_BUY))
   //    {
   //       g_trade.Buy(adjustedLot, _Symbol, entryPrice, sl, tp, InpComment);
   //    }
   // }

   Comment("BigB EA Running - No active position");
}

double calculateLotSize(double slPoints, double entryPrice)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   long accountLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if (freeMargin <= 0.0 || accountLeverage <= 0 || contractSize <= 0.0 || entryPrice <= 0.0)
      return 0.0;

   double maxLotByMargin = (freeMargin * accountLeverage * 0.98) / (contractSize * entryPrice);
   maxLotByMargin = MathFloor(maxLotByMargin / lotStep) * lotStep;

   if (maxLotByMargin < minVolume)
      return 0.0;

   double lotByRisk = maxVolume;
   if (InpLotType == Proportional_Lot)
   {
      // Proportional lot calculation: 0.01 * floor(balance / baseBalance)
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if (InpBaseBalance > 0.0 && accountBalance > 0.0)
      {
         int multiplier = (int)MathRound(accountBalance / InpBaseBalance);
         lotByRisk = MathMax(multiplier * 0.01, 0.01); // Ensure atleast 0.01 lots
      }
      else
      {
         lotByRisk = 0.01; // Default to minimum
      }
   }
   else if (InpLotType != Fixed_Lots)
   {
      double risk = 0.0;
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equityBalance = AccountInfoDouble(ACCOUNT_EQUITY);

      switch (InpLotType)
      {
      case Pct_Balance:
         risk = accountBalance * g_riskPercent / 100.0;
         break;
      case Pct_Equity:
         risk = equityBalance * g_riskPercent / 100.0;
         break;
      case Pct_Free_Margin:
         risk = freeMargin * g_riskPercent / 100.0;
         break;
      }

      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

      if (tickSize > 0.0 && tickValue > 0.0 && slPoints > 0.0)
      {
         double moneyPerLot = slPoints / tickSize * tickValue;
         if (moneyPerLot > 0.0)
            lotByRisk = risk / moneyPerLot;
      }
   }
   else
   {
      lotByRisk = InpFixedLots;
   }

   lotByRisk = MathFloor(lotByRisk / lotStep) * lotStep;

   double finalLot = MathMin(maxLotByMargin, lotByRisk);

   if (finalLot > maxVolume && maxVolume > 0.0)
      finalLot = maxVolume;

   if (finalLot < minVolume)
      return 0.0;

   return finalLot;
}

double adjustLotForMargin(double desiredLot, ENUM_ORDER_TYPE orderType, double orderPrice)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if (volumeStep <= 0.0)
      volumeStep = minVolume;

   if (orderPrice <= 0.0)
      return 0.0;

   double cappedLot = desiredLot;
   if (maxVolume > 0.0 && cappedLot > maxVolume)
      cappedLot = maxVolume;

   if (cappedLot < minVolume)
      cappedLot = minVolume;

   ENUM_ORDER_TYPE marginType = orderType;
   switch (orderType)
   {
   case ORDER_TYPE_BUY_STOP:
   case ORDER_TYPE_BUY_LIMIT:
   case ORDER_TYPE_BUY_STOP_LIMIT:
      marginType = ORDER_TYPE_BUY;
      break;
   case ORDER_TYPE_SELL_STOP:
   case ORDER_TYPE_SELL_LIMIT:
   case ORDER_TYPE_SELL_STOP_LIMIT:
      marginType = ORDER_TYPE_SELL;
      break;
   default:
      break;
   }

   double marginPrice = orderPrice;
   if (marginType == ORDER_TYPE_BUY)
      marginPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else if (marginType == ORDER_TYPE_SELL)
      marginPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int stepsAvailable = (int)((cappedLot - minVolume) / volumeStep + 0.0000001);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   for (int step = stepsAvailable; step >= 0; --step)
   {
      double candidateLot = minVolume + step * volumeStep;
      candidateLot = NormalizeDouble(candidateLot, 2);

      if (candidateLot < minVolume - 1e-8)
         continue;

      double requiredMargin = 0.0;
      if (!OrderCalcMargin(marginType, _Symbol, candidateLot, marginPrice, requiredMargin))
         return 0.0;

      if (requiredMargin <= freeMargin)
         return candidateLot;
   }

   return 0.0;
}

bool CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type)
{
   MqlTick mqltick;
   SymbolInfoTick(symb, mqltick);
   double price = mqltick.ask;
   if (type == ORDER_TYPE_SELL)
      price = mqltick.bid;

   double margin = 0.0;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   if (!OrderCalcMargin(type, symb, lots, price, margin))
   {
      Print("Error in ", __FUNCTION__, " code=", GetLastError());
      return false;
   }

   if (margin > free_margin)
   {
      Print("Not enough money for ", EnumToString(type), " ", lots, " ", symb, " Error code=", GetLastError());
      return false;
   }

   return true;
}

bool CheckMoneyForPendingOrder(string symb, double lots, ENUM_ORDER_TYPE type, double orderPrice)
{
   double margin = 0.0;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   if (!OrderCalcMargin(type, symb, lots, orderPrice, margin))
      return false;

   if (margin > free_margin)
      return false;

   return true;
}
//+------------------------------------------------------------------+
//|                    ZeroMQ Signal Receiver Functions               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Initialize ZeroMQ connection                                       |
//+------------------------------------------------------------------+
bool InitializeZMQ()
{
   // Build endpoint
   g_zmqEndpoint = InpProtocol + InpIPAddress + ":" + InpPort;

   // Create context
   g_context = new Context("CTV_Receiver");
   if (g_context == NULL)
   {
      Print("Failed to create ZMQ context");
      return false;
   }

   // Create PULL socket (receiver)
   g_zmqSocket = new Socket(g_context, ZMQ_PULL);
   if (g_zmqSocket == NULL)
   {
      Print("Failed to create ZMQ socket");
      return false;
   }

   // Connect to transmitter
   if (!g_zmqSocket.connect(g_zmqEndpoint))
   {
      Print("Failed to connect to: ", g_zmqEndpoint);
      Print("Error: ", Zmq::errorMessage());
      return false;
   }

   Print("ZMQ Connected to: ", g_zmqEndpoint);
   return true;
}

//+------------------------------------------------------------------+
//| Timer function - High-frequency signal checking                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Check for incoming signals continuously
   // Process ALL available messages in queue for zero latency
   CheckForSignals();
}

//+------------------------------------------------------------------+
//| Check for incoming signals - Process all in queue                 |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   if (g_zmqSocket == NULL)
      return;

   // Process ALL messages in queue for zero latency
   int processedCount = 0;
   while (true)
   {
      ZmqMsg msg;

      // Non-blocking receive
      if (!g_zmqSocket.recv(msg, true))
         break; // No more messages

      // Get data from message
      string jsonString = msg.getData();

      if (StringLen(jsonString) > 0)
      {
         // Process the JSON signal immediately
         ProcessJSONSignal(jsonString);
         processedCount++;
      }
   }

   // Optional: Log batch processing
   if (processedCount > 1 && InpEnableLogging)
   {
      Print("Processed ", processedCount, " signals in batch");
   }
}

//+------------------------------------------------------------------+
//| Process received JSON signal                                       |
//+------------------------------------------------------------------+
void ProcessJSONSignal(string jsonString)
{
   // Start latency measurement
   ulong startTime = 0;
   if (InpShowLatencyStats)
      startTime = GetMicrosecondCount();

   if (InpEnableLogging)
      Print("Received JSON: ", jsonString);

   // Parse JSON
   CJAVal json;
   if (!json.Deserialize(jsonString))
   {
      Print("ERROR: Failed to parse JSON: ", jsonString);
      return;
   }

   // Extract signal and symbol
   string signal = json["signal"].ToStr();
   string symbol = json["symbol"].ToStr();

   if (signal == "" || symbol == "")
   {
      Print("ERROR: Missing signal or symbol in JSON");
      return;
   }

   // Map symbol if enabled
   string receiverSymbol = MapSymbol(symbol);

   // Verify symbol exists
   if (!SymbolSelect(receiverSymbol, true))
   {
      Print("ERROR: Symbol not available: ", receiverSymbol, " (original: ", symbol, ")");
      return;
   }

   // Check for existing positions if MaxOneTrade is enabled
   if (InpMaxOneTrade)
   {
      int ourPositions = 0;
      for (int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if (g_pos.SelectByIndex(i))
         {
            if (g_pos.Symbol() == receiverSymbol && g_pos.Magic() == InpMagicNumber)
            {
               ourPositions++;
            }
         }
      }

      if (ourPositions > 0)
      {
         if (InpEnableLogging)
            Print("Signal REJECTED: Max one trade allowed. Existing positions for ", receiverSymbol, ": ", ourPositions);
         return;
      }
   }

   // Check if trade already happened on current candle
   if (InpMaxOneTradePerCandle && wasTradeOnCurrentCandle(receiverSymbol))
   {
      if (InpEnableLogging)
         Print("Signal REJECTED: Trade already executed on current candle for ", receiverSymbol);
      return;
   }

   // Calculate lot size using EA's settings
   double lotSize = calculateLotSize(g_SLPoints * _Point, SymbolInfoDouble(receiverSymbol, SYMBOL_ASK));
   lotSize = normalizeVolume(lotSize);

   if (lotSize <= 0.0)
   {
      Print("ERROR: Invalid lot size calculated: ", lotSize);
      return;
   }

   // Determine order type
   ENUM_ORDER_TYPE orderType;
   bool isBuy = false;

   if (signal == "BUY")
   {
      orderType = ORDER_TYPE_BUY;
      isBuy = true;
   }
   else if (signal == "SELL")
   {
      orderType = ORDER_TYPE_SELL;
      isBuy = false;
   }
   else
   {
      Print("ERROR: Unknown signal type: ", signal);
      return;
   }

   // Validate with volume filter before executing trade
   if (!validateTradeWithVolume(isBuy))
   {
      if (InpEnableLogging)
         Print("Signal REJECTED by volume filter: ", signal, " on ", receiverSymbol);
      return;
   }

   // Validate with candle open filter before executing trade
   if (!validateTradeWithCandleOpen(isBuy))
   {
      if (InpEnableLogging)
         Print("Signal REJECTED by candle open filter: ", signal, " on ", receiverSymbol);
      return;
   }

   // Validate signals with SAR filter if enabled
   // Use CURRENT market conditions (bar 0) for trend validation at execution time
   if (InpUseSARFilter)
   {
      if (CopyBuffer(g_sarHandle, 0, 0, 3, g_sarBuffer) > 0)
      {
         // Always check bar 0 (current bar) for live trend validation
         double currentSAR = g_sarBuffer[0];
         double currentBid = SymbolInfoDouble(receiverSymbol, SYMBOL_BID);
         double currentAsk = SymbolInfoDouble(receiverSymbol, SYMBOL_ASK);

         // BUY: SAR must be below current bid (bullish trend)
         // Check live price to ensure trend hasn't reversed since signal
         if (isBuy && currentSAR >= currentBid)
         {
            Print("BUY signal rejected by SAR filter. SAR=", currentSAR, " >= Bid=", currentBid, " (trend not bullish at execution)");
            return;
         }

         // SELL: SAR must be above current ask (bearish trend)
         // Check live price to ensure trend hasn't reversed since signal
         if (!isBuy && currentSAR <= currentAsk)
         {
            Print("SELL signal rejected by SAR filter. SAR=", currentSAR, " <= Ask=", currentAsk, " (trend not bearish at execution)");
            return;
         }
      }
      else
      {
         Print("Warning: Failed to copy SAR buffer. Error: ", GetLastError());
      }
   }

   // Get current prices
   double entryPrice = isBuy ? SymbolInfoDouble(receiverSymbol, SYMBOL_ASK) : SymbolInfoDouble(receiverSymbol, SYMBOL_BID);

   // Calculate SL/TP
   double sl = 0, tp = 0;
   if (isBuy)
   {
      sl = entryPrice - g_SLPoints * _Point;
      tp = entryPrice + g_TPPoints * _Point;
   }
   else
   {
      sl = entryPrice + g_SLPoints * _Point;
      tp = entryPrice - g_TPPoints * _Point;
   }

   // Validate stop levels
   validateStopLevels(entryPrice, sl, tp, orderType);

   // Final margin check
   if (!CheckMoneyForTrade(receiverSymbol, lotSize, orderType))
   {
      Print("ERROR: Insufficient margin for ", receiverSymbol, " volume ", lotSize);
      return;
   }

   // Execute trade immediately
   bool result = false;
   if (isBuy)
      result = g_trade.Buy(lotSize, receiverSymbol, 0, sl, tp, InpComment);
   else
      result = g_trade.Sell(lotSize, receiverSymbol, 0, sl, tp, InpComment);

   if (result)
   {
      if (InpEnableLogging)
      {
         string symbolDisplay = (receiverSymbol != symbol) ? symbol + "→" + receiverSymbol : receiverSymbol;
         Print("✓ EXECUTED: ", symbolDisplay, " ", signal, " ", lotSize, " lots | Ticket: ", g_trade.ResultOrder());
      }
   }
   else
   {
      Print("✗ EXECUTION FAILED: ", receiverSymbol, " ", signal, " - ", g_trade.ResultRetcode(),
            " - ", g_trade.ResultRetcodeDescription());
   }

   // Show latency statistics
   if (InpShowLatencyStats && startTime > 0)
   {
      ulong endTime = GetMicrosecondCount();
      double latencyMs = (endTime - startTime) / 1000.0;
      Print("⚡ Processing Latency: ", DoubleToString(latencyMs, 2), "ms");
   }
}

//+------------------------------------------------------------------+
//| Map transmitter symbol to receiver symbol                         |
//+------------------------------------------------------------------+
string MapSymbol(string transmitterSymbol)
{
   if (!InpEnableSymbolMapping)
      return transmitterSymbol;

   // 1. Check manual mappings first (highest priority)
   for (int i = 0; i < g_manualMapCount; i++)
   {
      if (g_manualSymbolMaps[i].transmitterSymbol == transmitterSymbol)
      {
         if (InpEnableLogging)
            Print("Symbol mapped (manual): ", transmitterSymbol, " → ", g_manualSymbolMaps[i].receiverSymbol);
         return g_manualSymbolMaps[i].receiverSymbol;
      }
   }

   // 2. Apply receiver suffix if specified
   string mappedSymbol = transmitterSymbol;
   if (InpReceiverSuffix != "")
   {
      mappedSymbol = transmitterSymbol + InpReceiverSuffix;
   }

   // 3. Try the mapped symbol directly
   if (SymbolSelect(mappedSymbol, true))
   {
      if (mappedSymbol != transmitterSymbol && InpEnableLogging)
         Print("Symbol mapped (suffix): ", transmitterSymbol, " → ", mappedSymbol);
      return mappedSymbol;
   }

   // 4. Auto-handle suffixes if enabled
   if (InpAutoHandleSuffixes)
   {
      // Try common suffix variations
      string suffixes[] = {".c", ".raw", ".pro", ".ecn", ".a", ".b", ".m", "#", "_", "!", ".pc", ".sc", ".cent"};

      for (int i = 0; i < ArraySize(suffixes); i++)
      {
         string testSymbol = transmitterSymbol + suffixes[i];
         if (SymbolSelect(testSymbol, true))
         {
            if (InpEnableLogging)
               Print("Symbol mapped (auto-suffix): ", transmitterSymbol, " → ", testSymbol);
            return testSymbol;
         }
      }

      // Try removing suffix from transmitter symbol
      int dotPos = StringFind(transmitterSymbol, ".");
      if (dotPos > 0)
      {
         string baseSymbol = StringSubstr(transmitterSymbol, 0, dotPos);
         if (SymbolSelect(baseSymbol, true))
         {
            if (InpEnableLogging)
               Print("Symbol mapped (strip-suffix): ", transmitterSymbol, " → ", baseSymbol);
            return baseSymbol;
         }
      }
   }

   // 5. Return original if no mapping found
   if (InpEnableLogging && mappedSymbol != transmitterSymbol)
      Print("Symbol mapping failed, using original: ", transmitterSymbol);

   return transmitterSymbol;
}

//+------------------------------------------------------------------+
//| Load manual symbol mappings from input string                     |
//+------------------------------------------------------------------+
void LoadManualSymbolMappings()
{
   if (InpManualSymbolMaps == "")
   {
      g_manualMapCount = 0;
      return;
   }

   // Parse semicolon-separated pairs: "XAUUSD,GOLD;EURUSD,EUR.USD"
   string pairs[];
   int pairCount = StringSplit(InpManualSymbolMaps, ';', pairs);

   if (pairCount <= 0)
   {
      g_manualMapCount = 0;
      return;
   }

   ArrayResize(g_manualSymbolMaps, pairCount);
   g_manualMapCount = 0;

   for (int i = 0; i < pairCount; i++)
   {
      string mapping[];
      if (StringSplit(pairs[i], ',', mapping) == 2)
      {
         g_manualSymbolMaps[g_manualMapCount].transmitterSymbol = mapping[0];
         g_manualSymbolMaps[g_manualMapCount].receiverSymbol = mapping[1];
         g_manualMapCount++;
         Print("Manual symbol mapping loaded: ", mapping[0], " → ", mapping[1]);
      }
   }

   Print("Total manual symbol mappings loaded: ", g_manualMapCount);
}

//+------------------------------------------------------------------+
//|                    Volume Filter Functions                        |
//+------------------------------------------------------------------+
void initVolumeFilter()
{
   // Create custom Volumes indicator
   g_volumeHandle = iCustom(_Symbol, _Period, "Examples\\Volumes", InpVolumeType);

   if (g_volumeHandle == INVALID_HANDLE)
   {
      Print("Error creating Volume indicator: ", GetLastError());
      Print("Make sure Volumes.mq5 is compiled in Indicators/Examples folder");
      return;
   }

   // Set buffers as series for easier access
   ArraySetAsSeries(g_volumeBuffer, true);
   ArraySetAsSeries(g_volumeColorBuffer, true);

   Print("Volume Filter initialized successfully");
}

bool validateTradeWithVolume(bool isBuy)
{
   if (!InpUseVolumeFilter)
      return true; // Filter disabled, allow trade

   if (g_volumeHandle == INVALID_HANDLE)
   {
      Print("Volume indicator not initialized, skipping volume validation");
      return true; // If indicator failed to initialize, don't block trades
   }

   // Copy volume color buffer (0=green, 1=red)
   if (CopyBuffer(g_volumeHandle, 1, 0, 2, g_volumeColorBuffer) <= 0)
   {
      Print("Failed to copy volume color buffer: ", GetLastError());
      return true; // On error, allow trade
   }

   // Get current volume candle color (index 0 is current candle)
   double currentColor = g_volumeColorBuffer[0];

   if (isBuy)
   {
      // For buy trades, volume candle must be green (color = 0)
      if (currentColor == 0.0)
      {
         Print("Volume filter: BUY validated - Volume candle is GREEN");
         return true;
      }
      else
      {
         Print("Volume filter: BUY rejected - Volume candle is RED");
         return false;
      }
   }
   else // Sell trade
   {
      // For sell trades, volume candle must be red (color = 1)
      if (currentColor == 1.0)
      {
         Print("Volume filter: SELL validated - Volume candle is RED");
         return true;
      }
      else
      {
         Print("Volume filter: SELL rejected - Volume candle is GREEN");
         return false;
      }
   }
}

void manageVolumeBasedExits()
{
   if (!InpUseVolumeExitMonitor)
      return;

   if (g_volumeHandle == INVALID_HANDLE)
   {
      Print("Volume indicator not initialized, skipping volume exit monitoring");
      return;
   }

   // Copy volume color buffer
   if (CopyBuffer(g_volumeHandle, 1, 0, 2, g_volumeColorBuffer) <= 0)
   {
      Print("Failed to copy volume color buffer for exit monitoring: ", GetLastError());
      return;
   }

   // Get current volume candle color
   double currentColor = g_volumeColorBuffer[0];

   // Check all open positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_pos.SelectByIndex(i))
         continue;

      if (g_pos.Symbol() != _Symbol)
         continue;
      if (g_pos.Magic() != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = g_pos.PositionType();

      // Close buy positions when volume candle turns red (color = 1)
      if (posType == POSITION_TYPE_BUY && currentColor == 1.0)
      {
         if (safePositionClose(g_pos.Ticket()))
            Print("Volume Exit: Closed BUY position - Volume candle turned RED");
      }
      // Close sell positions when volume candle turns green (color = 0)
      else if (posType == POSITION_TYPE_SELL && currentColor == 0.0)
      {
         if (safePositionClose(g_pos.Ticket()))
            Print("Volume Exit: Closed SELL position - Volume candle turned GREEN");
      }
   }
}

//+------------------------------------------------------------------+
//|                Candle Open Filter Functions                       |
//+------------------------------------------------------------------+
bool validateTradeWithCandleOpen(bool isBuy)
{
   if (!InpUseCandleOpenFilter)
      return true; // Filter disabled, allow trade

   // Get current candle's open price (bar 0)
   double currentOpen = iOpen(_Symbol, _Period, 0);

   // Get current market prices
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (isBuy)
   {
      // For BUY: current price (ask) must be greater than current candle's open
      if (currentAsk > currentOpen)
      {
         Print("Candle Open filter: BUY validated - Ask (", DoubleToString(currentAsk, _Digits),
               ") > Candle Open (", DoubleToString(currentOpen, _Digits), ")");
         return true;
      }
      else
      {
         Print("Candle Open filter: BUY rejected - Ask (", DoubleToString(currentAsk, _Digits),
               ") <= Candle Open (", DoubleToString(currentOpen, _Digits), ")");
         return false;
      }
   }
   else // Sell trade
   {
      // For SELL: current price (bid) must be less than current candle's open
      if (currentBid < currentOpen)
      {
         Print("Candle Open filter: SELL validated - Bid (", DoubleToString(currentBid, _Digits),
               ") < Candle Open (", DoubleToString(currentOpen, _Digits), ")");
         return true;
      }
      else
      {
         Print("Candle Open filter: SELL rejected - Bid (", DoubleToString(currentBid, _Digits),
               ") >= Candle Open (", DoubleToString(currentOpen, _Digits), ")");
         return false;
      }
   }
}

void manageCandleOpenBasedExits()
{
   if (!InpUseCandleOpenExitMonitor)
      return;

   // Get current candle's open price (bar 0)
   double currentOpen = iOpen(_Symbol, _Period, 0);

   // Get current market prices
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Check all open positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_pos.SelectByIndex(i))
         continue;

      if (g_pos.Symbol() != _Symbol)
         continue;
      if (g_pos.Magic() != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE posType = g_pos.PositionType();

      // Close buy positions when current price goes below current candle's open
      if (posType == POSITION_TYPE_BUY && currentBid < currentOpen)
      {
         if (safePositionClose(g_pos.Ticket()))
            Print("Candle Open Exit: Closed BUY position - Bid (", DoubleToString(currentBid, _Digits),
                  ") fell below Candle Open (", DoubleToString(currentOpen, _Digits), ")");
      }
      // Close sell positions when current price goes above current candle's open
      else if (posType == POSITION_TYPE_SELL && currentAsk > currentOpen)
      {
         if (safePositionClose(g_pos.Ticket()))
            Print("Candle Open Exit: Closed SELL position - Ask (", DoubleToString(currentAsk, _Digits),
                  ") rose above Candle Open (", DoubleToString(currentOpen, _Digits), ")");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a trade was executed on the current candle               |
//+------------------------------------------------------------------+
bool wasTradeOnCurrentCandle(string symbol)
{
   // Get the time of the current candle open
   // Note: Using _Period for the candle timeframe. If EA trades multiple signals
   // but is on one chart, this restriction applies to the chart's timeframe.
   datetime currentCandleOpen = iTime(_Symbol, _Period, 0);

   // Select deal history starting from the candle open time
   if (!HistorySelect(currentCandleOpen, TimeCurrent()))
      return false;

   int totalDeals = HistoryDealsTotal();
   for (int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if (dealTicket == 0)
         continue;

      // Check if this deal belongs to our EA and the specific symbol
      string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

      // We look for ENTRY_IN deals (new trades)
      if (dealSymbol == symbol && dealMagic == InpMagicNumber && dealEntry == DEAL_ENTRY_IN)
      {
         return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Validate time format HH:MM:SS                                     |
//+------------------------------------------------------------------+
bool validateTimeFormat(string timeStr)
{
   // Check if string is empty
   if (StringLen(timeStr) == 0)
      return false;

   // Split by colon separator
   string parts[];
   int count = StringSplit(timeStr, ':', parts);

   // Must have exactly 3 parts (HH:MM:SS)
   if (count != 3)
      return false;

   // Validate each part length
   if (StringLen(parts[0]) != 2 || StringLen(parts[1]) != 2 || StringLen(parts[2]) != 2)
      return false;

   // Check if all characters are digits
   for (int i = 0; i < 3; i++)
   {
      for (int j = 0; j < 2; j++)
      {
         ushort ch = StringGetCharacter(parts[i], j);
         if (ch < '0' || ch > '9')
            return false;
      }
   }

   // Convert to integers and validate ranges
   int hours = (int)StringToInteger(parts[0]);
   int minutes = (int)StringToInteger(parts[1]);
   int seconds = (int)StringToInteger(parts[2]);

   // Validate ranges: hours 0-23, minutes 0-59, seconds 0-59
   if (hours < 0 || hours > 23)
      return false;
   if (minutes < 0 || minutes > 59)
      return false;
   if (seconds < 0 || seconds > 59)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool isWithinTradingSession()
{
   datetime sessionStart = StringToTime(InpSessionStart);
   datetime sessionEnd = StringToTime(InpSessionEnd);
   datetime currentTime = TimeCurrent();
   if (currentTime >= sessionStart && currentTime <= sessionEnd)
      return true;
   return false;
}
//+------------------------------------------------------------------+
