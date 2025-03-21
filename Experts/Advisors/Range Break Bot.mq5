#property strict
#include <Trade/Trade.mqh> 

CTrade trade; 

input double LotSize = 0.05;
input double MartingaleMultiplier = 2.3;
input double TakeProfitRatio = 1.03;
input double StopLossRatio = 0.98;
input int RangePeriod = 5;  // Minutes
input int TradeTimeout = 60; // Timeout in minutes
input double MaxDrawdown = 0.05; // 5% drawdown from peak profit
input double TrailingStopDistance = 2; // Trailing stop distance in points

struct TradeInfo {
    bool active;
    double stopLoss;
    double takeProfit;
    double entryPrice;
    datetime entryTime;

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

double rangeThreshold = 0.05;  // 2% range threshold

int OnInit()
{
    Print("Range Breakout Bot Initialized");
    tradeInfo.active = false;
    DrawTrendlines();
    return INIT_SUCCEEDED;
}

void OnTick() {
    double rangePips = (highRange - lowRange) / _Point;
    double priceDifference = highRange - lowRange;
    double priceAtClose = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double rangePercentage = priceDifference / priceAtClose;

    if (rangePercentage > rangeThreshold) {
        Print("Range is greater than 2%, no trades will be opened.");

        RemoveTrendlines();
        GetRange();
        return; // Do not open trades if range is greater than 2%
    }

    if (!tradeInfo.active && !PositionSelect(_Symbol)) {
        retestConfirmed = false;
        entryTime = TimeCurrent(); // Store entry time for timeout

    }

    if (!retestConfirmed) {
        CheckForRetest();
    }
    CheckTradeTimeout();
    CheckForNoActiveTrades();
    // updateTrailingStop();
    
}

void GetRange()
{
    double highestHigh = -1;
    double lowestLow = -1;
    int highestIndex = -1;
    int lowestIndex = -1;

    for (int i = 3; i <= 23; i++) { // Start from the 2nd candle (index 1) to 10th candle (index 9)
        double currentHigh = iHigh(_Symbol, PERIOD_M15, i);
        double currentLow = iLow(_Symbol, PERIOD_M15, i);

        if (highestHigh == -1 || currentHigh > highestHigh) {
            highestHigh = currentHigh;
            highestIndex = i;
        }

        if (lowestLow == -1 || currentLow < lowestLow) {
            lowestLow = currentLow;
            lowestIndex = i;
        }
    }
    highRange = highestHigh;
    lowRange = lowestLow;

    Print("High Range: ", highRange, " | Low Range: ", lowRange);
}

void DrawTrendlines()
{
    if (ObjectFind(0, highLineName) < 0) {
        GetRange();

        datetime time1 = iTime(_Symbol, PERIOD_M15, 3); // Time of the 2nd candlestick
        datetime time2 = iTime(_Symbol, PERIOD_M15, 23); // Time of the 10th candlestick
        double price1_high = highRange;  // Use the highest high from GetRange
        double price1_low = lowRange;   // Use the lowest low from GetRange

        ObjectCreate(0, highLineName, OBJ_TREND, 0, time1, price1_high, time2, price1_high);
        ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);  // Do not extend the line
        ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 3);  // Make the line thicker

        ObjectCreate(0, lowLineName, OBJ_TREND, 0, time1, price1_low, time2, price1_low);
        ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);  // Do not extend the line
        ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 3);  // Make the line thicker
    }
}


void CheckForRetest() {
    double lastClose = iClose(_Symbol, PERIOD_M15, 1);
    double lastOpen = iOpen(_Symbol, PERIOD_M15, 1);
    double currentClose = iClose(_Symbol, PERIOD_M15, 0);
    double currentLow = iLow(_Symbol, PERIOD_M15, 0);
    double currentHigh = iHigh(_Symbol, PERIOD_M15, 0);

    // Check if the price breaks above highRange for sell (bearish condition)
    if (lastClose > highRange && lastOpen < lastClose) {
        if (currentClose > highRange) {  // Price breaks above highRange
            retestConfirmed = true;

            // Open a Sell trade at the highRange level
            OpenTrade(ORDER_TYPE_SELL, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_BID), highRange);  
            // Open a Buy trade at the highRange level (for hedging)
            OpenTrade(ORDER_TYPE_BUY, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), highRange);

            Print("✅ Buy and Sell trades opened after price broke above highRange.");
        }
    } 
    // Check if the price breaks below lowRange for buy (bullish condition)
    else if (lastClose < lowRange && lastOpen > lastClose) {
        if (currentClose < lowRange) {  // Price breaks below lowRange
            retestConfirmed = true;

            // Open a Buy trade at the lowRange level
            OpenTrade(ORDER_TYPE_BUY, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), lowRange);  
            // Open a Sell trade at the lowRange level (for hedging)
            OpenTrade(ORDER_TYPE_SELL, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_BID), lowRange);

            Print("✅ Buy and Sell trades opened after price broke below lowRange.");
        }
    }
}



void OpenTrade(int type, double lots, double price, double trendLine) {
    double stopLoss = 0.05;  // No stop loss
    double takeProfit = trendLine;  // Set take profit based on trend line (highRange or lowRange)
    
    // Normalize the take profit price
    takeProfit = NormalizeDouble(takeProfit, _Digits);

    // Record the entry time and other trade information
    tradeInfo.entryTime = TimeCurrent();
    tradeInfo.stopLoss = stopLoss;
    tradeInfo.takeProfit = takeProfit;
    tradeInfo.entryPrice = price;

    // Use CTrade to open a trade
    if (type == ORDER_TYPE_BUY) {
        if (trade.Buy(lots, _Symbol, price, stopLoss, takeProfit)) {
            Print("✅ Buy trade opened: Lots: ", lots);
            tradeInfo.active = true;
        } else {
            Print("Buy trade failed: ", GetLastError());
        }
    } else if (type == ORDER_TYPE_SELL) {
        if (trade.Sell(lots, _Symbol, price, stopLoss, takeProfit)) {
            Print("✅ Sell trade opened: Lots: ", lots);
            tradeInfo.active = true;
        } else {
            Print("Sell trade failed: ", GetLastError());
        }
    }
}



// void updateTrailingStop() {
//     if (tradeInfo.active && PositionSelect(_Symbol)) {
//         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
//         double stopLoss = PositionGetDouble(POSITION_SL);  // Get current stop loss
//         double trailStop = 0;

//         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
//             trailStop = currentPrice - TrailingStopDistance * _Point;

//             if (trailStop > stopLoss) {
//                 stopLoss = trailStop;
//             }
//         }
//         else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
//             trailStop = currentPrice + TrailingStopDistance * _Point;

//             if (trailStop < stopLoss) {
//                 stopLoss = trailStop;
//             }
//         }

//         if (stopLoss != PositionGetDouble(POSITION_SL)) {
//             MqlTradeRequest request = {};
//             MqlTradeResult result = {};
//             request.action = TRADE_ACTION_SLTP;
//             request.symbol = _Symbol;
//             request.position = PositionGetInteger(POSITION_TICKET);
//             request.sl = NormalizeDouble(stopLoss, _Digits);
//             request.deviation = 10;
//             request.magic = 12345;  // Unique magic number for the trade

//             if (OrderSend(request, result)) {
//                 if (result.retcode == TRADE_RETCODE_DONE) {
//                     Print("Trailing stop updated: ", stopLoss);
//                 } else {
//                     Print("Failed to update trailing stop. Error code: ", result.retcode);
//                 }
//             } else {
//                 Print("Error in modifying the position: ", GetLastError());
//             }
//         }
//     }
// }

void CheckTradeTimeout() {
    if (tradeInfo.active) {
        datetime currentTime = TimeCurrent();
        if (currentTime - tradeInfo.entryTime >= 30 * 60) {  // If 1 hour has passed
            Print("Closing trade after 1 hour of runtime.");
            CheckTradeStatus();
            CloseTrade();  // Close the trade after 1 hour
        }
    }
}

void CheckTradeStatus() {
    if (tradeInfo.active) {
        double currentPrice = SymbolInfoDouble(_Symbol, (tradeInfo.stopLoss > tradeInfo.entryPrice) ? SYMBOL_BID : SYMBOL_ASK);

        if ((tradeInfo.stopLoss > tradeInfo.entryPrice && currentPrice >= tradeInfo.takeProfit) ||
            (tradeInfo.stopLoss < tradeInfo.entryPrice && currentPrice <= tradeInfo.takeProfit)) {
            Print("✅ Take Profit reached.");
            CloseTrade();  // Close the trade
            tradeInfo.active = false;  // Mark the trade as inactive
        }
        else if ((tradeInfo.stopLoss > tradeInfo.entryPrice && currentPrice <= tradeInfo.stopLoss) ||
                 (tradeInfo.stopLoss < tradeInfo.entryPrice && currentPrice >= tradeInfo.stopLoss)) {
            Print("❌ Stop Loss reached.");
            CloseTrade();  // Close the trade
            tradeInfo.active = false;  // Mark the trade as inactive
        }
    }
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

    if (PositionsTotal() == 0) {
        Print("✅ All trades successfully closed.");
    } else {
        Print("🚨 Some trades are still open — check for partial closes or errors.");
    }
}

void RemoveTrendlines() {
    if (ObjectFind(0, highLineName) >= 0) {
        ObjectDelete(0, highLineName);
    }
    if (ObjectFind(0, lowLineName) >= 0) {
        ObjectDelete(0, lowLineName);
    }
}

void CheckForNoActiveTrades() {
    if (!tradeInfo.active && PositionsTotal() == 0) {
        Print("No active trades, removing previous trendlines and finding a new range.");
        RemoveTrendlines();  // Remove old trendlines
        DrawTrendlines();    // Draw new trendlines based on updated range
    }
}
