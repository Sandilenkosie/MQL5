//+------------------------------------------------------------------+
//|                                                      RangeBot.mq5 | 
//|                        © 2024, YourName                          |
//|                           Version 1.5                            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh> 

CTrade trade; 

input double LotSize = 0.01;
input double MartingaleMultiplier = 2.3;
input double TakeProfitRatio = 1.03;
input double StopLossRatio = 0.98;
input int RangePeriod = 5;  // Minutes
input int TradeTimeout = 60; // Timeout in minutes
input double MaxDrawdown = 0.05; // 5% drawdown from peak profit

// Structure to track trade details
struct TradeInfo {
    bool active;
    double stopLoss;
    double takeProfit;
    double entryPrice;
    datetime entryTime;

    // Constructor to initialize the struct members
    TradeInfo() {
        active = false;
        stopLoss = 0;
        takeProfit = 0;
        entryPrice = 0;
        entryTime = 0;
    }
};

TradeInfo tradeInfo;

double highRange, lowRange;
datetime entryTime;
int totalLosses = 0;
string highLineName = "HighRangeLine";  // Name for high range line
string lowLineName = "LowRangeLine";   // Name for low range line

bool breakoutOccurred = false;
bool retestConfirmed = false;

double rangeThreshold = 0.005;  // 2% range threshold

int OnInit()
{
    Print("Range Breakout Bot Initialized");
    tradeInfo.active = false;

    // Draw trendlines once on initialization
    DrawTrendlines();
    return INIT_SUCCEEDED;
}

void OnTick() {
    // Calculate the range in pips
    double rangePips = (highRange - lowRange) / _Point;

    // Check if the range is greater than 2%
    double priceDifference = highRange - lowRange;
    double priceAtClose = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double rangePercentage = priceDifference / priceAtClose;

    if (rangePercentage > rangeThreshold) {
        Print("Range is greater than 2%, no trades will be opened.");

        RemoveTrendlines();
        // Get a new range
        GetRange();
        return; // Do not open trades if range is greater than 2%
    }

    // Ensure a trade is not active before checking for breakout
    if (!tradeInfo.active && SymbolInfoDouble(_Symbol, SYMBOL_ASK) > highRange && !PositionSelect(_Symbol)) {
        breakoutOccurred = true;
        retestConfirmed = false;
        entryTime = TimeCurrent(); // Store entry time for timeout
        Print("Breakout to buy detected.");
        // Here you should call OpenTrade function to actually open the trade
    }

    if (!tradeInfo.active && SymbolInfoDouble(_Symbol, SYMBOL_BID) < lowRange && !PositionSelect(_Symbol)) {
        breakoutOccurred = true;
        retestConfirmed = false;
        entryTime = TimeCurrent(); // Store entry time for timeout
        Print("Breakout to sell detected.");
        // Here you should call OpenTrade function to actually open the trade
    }

    // Confirm the retest and open a trade
    if (breakoutOccurred && !retestConfirmed) {
        CheckForRetest();
    }

    // Check if trades need to be checked for timeout or profit
    CheckTrades();

    CheckTradeTimeout();
    // Check for removal of trendlines and finding new range
    CheckForNoActiveTrades();
    
}

//+------------------------------------------------------------------+
//| Get the high and low range over the 2nd to 10th candles         |
//+------------------------------------------------------------------+
void GetRange()
{
    // Variables to store the highest high and lowest low
    double highestHigh = -1;
    double lowestLow = -1;
    int highestIndex = -1;
    int lowestIndex = -1;

    // Loop over the 2nd to the 10th candles (indexes 1 to 9)
    for (int i = 1; i <= 9; i++) { // Start from the 2nd candle (index 1) to 10th candle (index 9)
        double currentHigh = iHigh(_Symbol, PERIOD_M5, i);
        double currentLow = iLow(_Symbol, PERIOD_M5, i);

        // Update highest high
        if (highestHigh == -1 || currentHigh > highestHigh) {
            highestHigh = currentHigh;
            highestIndex = i;
        }

        // Update lowest low
        if (lowestLow == -1 || currentLow < lowestLow) {
            lowestLow = currentLow;
            lowestIndex = i;
        }
    }

    // Set highRange and lowRange based on the highest and lowest values found
    highRange = highestHigh;
    lowRange = lowestLow;

    Print("High Range: ", highRange, " | Low Range: ", lowRange);
}

//+------------------------------------------------------------------+
//| Draw or update the horizontal trendlines on the chart            |
//+------------------------------------------------------------------+
void DrawTrendlines()
{
    // Ensure the trendlines are drawn once, if they don't already exist
    if (ObjectFind(0, highLineName) < 0) {
        // Call GetRange to get the highest high and lowest low
        GetRange();

        // Create the high range horizontal trendline (constant price)
        datetime time1 = iTime(_Symbol, PERIOD_M5, 1); // Time of the 2nd candlestick
        datetime time2 = iTime(_Symbol, PERIOD_M5, 9); // Time of the 10th candlestick
        double price1_high = highRange;  // Use the highest high from GetRange
        double price1_low = lowRange;   // Use the lowest low from GetRange

        // Create the high range horizontal trendline (constant price)
        ObjectCreate(0, highLineName, OBJ_TREND, 0, time1, price1_high, time2, price1_high);
        ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);  // Do not extend the line
        ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 3);  // Make the line thicker

        // Create the low range horizontal trendline (constant price)
        ObjectCreate(0, lowLineName, OBJ_TREND, 0, time1, price1_low, time2, price1_low);
        ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);  // Do not extend the line
        ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 3);  // Make the line thicker
    }
}

//+------------------------------------------------------------------+
//| Check for retest and open the trade                             |
//+------------------------------------------------------------------+
void CheckForRetest()
{
    double lastClose = iClose(_Symbol, PERIOD_M5, 1);  // Last closed candle
    if (SymbolInfoDouble(_Symbol, SYMBOL_ASK) > highRange && lastClose > highRange) {  // Confirm retest above high range for buy
        retestConfirmed = true;
        OpenTrade(ORDER_TYPE_BUY, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
        Print("✅ Buy trade opened after retest.");
    } else if (SymbolInfoDouble(_Symbol, SYMBOL_BID) < lowRange && lastClose < lowRange) {  // Confirm retest below low range for sell
        retestConfirmed = true;
        OpenTrade(ORDER_TYPE_SELL, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_BID));
        Print("✅ Sell trade opened after retest.");
    }
}

void OpenTrade(int type, double lots, double price) {
    double stopLoss, takeProfit;
    double entryPrice = price; // Track the entry price

    // Ensure lowRange and highRange are properly initialized
    if (lowRange == 0 || highRange == 0) {
        Print("Error: lowRange or highRange not initialized.");
        return;
    }

    // For Buy orders, stop loss will be below the lowRange (support level)
    if (type == ORDER_TYPE_BUY) {
        stopLoss = lowRange;  // Set stop loss below the lowRange for buy
        takeProfit = price + (price - stopLoss) * 1.8;  // Take profit based on the stop loss distance
    }
    // For Sell orders, stop loss will be above the highRange (resistance level)
    else if (type == ORDER_TYPE_SELL) {
        stopLoss = highRange;  // Set stop loss above the highRange for sell
        takeProfit = price - (stopLoss - price) * 1.8;  // Take profit based on the stop loss distance
    }

    // Normalize the stop loss and take profit values
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = type;
    request.price = price;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "Range Breakout Bot";

    // Record the entry time
    tradeInfo.entryTime = TimeCurrent();
    tradeInfo.stopLoss = stopLoss;
    tradeInfo.takeProfit = takeProfit;
    tradeInfo.entryPrice = entryPrice;

    // Send the trade order using OrderSend() function
    if (OrderSend(request, result)) {
        if (result.retcode != TRADE_RETCODE_DONE) {
            Print("Order failed: ", result.retcode);  // Print the error code if the order fails
            Print("Error details: ", GetLastError());  // Get and print the specific error details
        } else {
            Print("✅ Trade opened: ", (type == ORDER_TYPE_BUY) ? "BUY" : "SELL", " | Lots: ", lots);
            tradeInfo.active = true;
        }
    } else {
        // This ensures you print the error if OrderSend fails to return expected value
        Print("OrderSend failed with error: ", GetLastError());
    }
}


void CheckTradeTimeout() {
    if (tradeInfo.active) {
        datetime currentTime = TimeCurrent();
        if (currentTime - tradeInfo.entryTime >= 120 * 60) {  // If 1 hour has passed
            Print("Closing trade after 1 hour of runtime.");
            CheckTradeStatus();
            CloseTrade();  // Close the trade after 1 hour
        }
    }
}

// Function to check if the trade hit TakeProfit or StopLoss
void CheckTradeStatus() {
    if (tradeInfo.active) {
        double currentPrice = SymbolInfoDouble(_Symbol, (tradeInfo.stopLoss > tradeInfo.entryPrice) ? SYMBOL_BID : SYMBOL_ASK);

        // Check if TakeProfit was hit
        if ((tradeInfo.stopLoss > tradeInfo.entryPrice && currentPrice >= tradeInfo.takeProfit) ||
            (tradeInfo.stopLoss < tradeInfo.entryPrice && currentPrice <= tradeInfo.takeProfit)) {
            Print("✅ Take Profit reached.");
            CloseTrade();  // Close the trade
            tradeInfo.active = false;  // Mark the trade as inactive
        }
        // Check if StopLoss was hit
        else if ((tradeInfo.stopLoss > tradeInfo.entryPrice && currentPrice <= tradeInfo.stopLoss) ||
                 (tradeInfo.stopLoss < tradeInfo.entryPrice && currentPrice >= tradeInfo.stopLoss)) {
            Print("❌ Stop Loss reached.");
            CloseTrade();  // Close the trade
            tradeInfo.active = false;  // Mark the trade as inactive
        }
    }
}

int CheckTrades() {
    int totalTrades = 0;

    // Loop through all open positions
    for (int i = 0; i < PositionsTotal(); i++) {
        // Use PositionSelect with just the symbol and check if the position is selected
        if (PositionSelect(Symbol())) {
            totalTrades++;
        }
    }

    return totalTrades; // Return the total number of open trades
}


void CloseTrade() {
    int totalPositions = PositionsTotal();

    if (totalPositions == 0) {
        Print("⚠️ No active positions to close.");
        return;
    }

    for (int i = totalPositions - 1; i >= 0; i--) {
        ulong positionTicket = PositionGetTicket(i);

        if (trade.PositionClose(positionTicket, -1)) {
            Print("✅ Successfully closed position: ", positionTicket);
        } else {
            Print("❌ Failed to close position: ", positionTicket, " | Error: ", GetLastError());
        }
    }

    // Final check to ensure all positions are gone
    if (PositionsTotal() == 0) {
        Print("✅ All trades successfully closed.");
    } else {
        Print("🚨 Some trades are still open — check for partial closes or errors.");
    }
}



//+------------------------------------------------------------------+
//| Remove all trendlines from the chart                             |
//+------------------------------------------------------------------+
void RemoveTrendlines() {
    // Remove high and low range trendlines if they exist
    if (ObjectFind(0, highLineName) >= 0) {
        ObjectDelete(0, highLineName);
    }
    if (ObjectFind(0, lowLineName) >= 0) {
        ObjectDelete(0, lowLineName);
    }
}

//+------------------------------------------------------------------+
//| Remove trendlines if no trades are active and find new range     |
//+------------------------------------------------------------------+
void CheckForNoActiveTrades() {
    // If no active trades and no open positions, remove trendlines and find a new range
    if (!tradeInfo.active && PositionsTotal() == 0) {
        Print("No active trades, removing previous trendlines and finding a new range.");
        RemoveTrendlines();  // Remove old trendlines
        DrawTrendlines();    // Draw new trendlines based on updated range
    }
}
