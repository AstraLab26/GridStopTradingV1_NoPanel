//+------------------------------------------------------------------+
//|                   GridStopTradingV1_NoPanel.mq5                    |
//|         EA lưới Stop (Buy/Sell Stop) - Bản nhẹ không panel         |
//+------------------------------------------------------------------+
#property copyright "Grid Stop Trading"
#property version   "1.0"
#property description "EA lưới chỉ lệnh Stop - Buy Stop trên gốc, Sell Stop dưới gốc. Gồng lãi, cân bằng lệnh, giờ hoạt động, dừng theo tích lũy."

#include <Trade\Trade.mqh>

//--- Enum cho hành động khi đạt TP tổng
enum ENUM_TP_ACTION
{
   TP_ACTION_STOP_EA = 0,    // Dừng EA
   TP_ACTION_RESET_EA = 1    // Reset EA
};

//--- Enum cho chế độ Trading Stop
enum ENUM_TRADING_STOP_MODE
{
   TRADING_STOP_MODE_OPEN = 0,    // Theo ngưỡng các lệnh mở
   TRADING_STOP_MODE_SESSION = 1, // Theo ngưỡng phiên
   TRADING_STOP_MODE_BOTH = 2     // Tổ hợp cả 2 (ưu tiên cái đạt trước)
};

//--- Enum cho chế độ gấp thếp (cấp số nhân hoặc cấp số cộng) - lot size
enum ENUM_MARTINGALE_MODE
{
   MARTINGALE_MODE_MULTIPLIER = 0,  // Cấp số nhân (x2, x4...)
   MARTINGALE_MODE_ARITHMETIC = 1   // Cấp số cộng (+0.01 mỗi bậc...)
};

//--- Enum cho chế độ khoảng cách lưới
enum ENUM_GRID_DISTANCE_MODE
{
   GRID_MODE_FIXED = 0,        // Cố định: bậc n cách n*x pip
   GRID_MODE_ARITHMETIC = 1    // Cấp số cộng: bậc 1 = x pip, bậc 2 = x+step, bậc 3 = x+2*step...
};

//--- Input parameters - Cài đặt lưới
input group "=== CÀI ĐẶT LƯỚI ==="
input ENUM_GRID_DISTANCE_MODE GridDistanceMode = GRID_MODE_FIXED; // Chế độ khoảng cách lưới (0=Cố định, 1=Cấp số cộng)
input double GridDistancePips = 20.0;           // Khoảng cách lưới cơ sở / bậc 1 (pips)
input double GridStepPips = 100.0;              // Khoảng cách lưới cố định (pips) - Cấp số cộng: bậc 1=100, bậc 2 cách bậc 1=200, bậc 3 cách bậc 2=300...
input bool AutoRefillOrders = true;             // Tự động bổ sung lệnh khi đóng
input int MaxOpenForStopRefill = 2;             // Tối đa lệnh mở mỗi chiều để bổ sung lệnh chờ (vd: 2 = có 2 lệnh Buy mở thì không bổ sung Buy Stop)

//--- Enum cho chế độ Take Profit
enum ENUM_TP_MODE
{
   TP_MODE_FIXED_PIPS = 0,   // TP cố định (pips)
   TP_MODE_GRID_LEVEL = 1    // TP theo lưới: lệnh bậc k → TP = giá bậc k+1
};

//--- Input parameters - Cài đặt lệnh Stop A (Buy Stop trên gốc, Sell Stop dưới gốc, có gấp thếp)
input group "=== CÀI ĐẶT LỆNH STOP A (BUY STOP & SELL STOP) ==="
input bool EnableStopOrders = true;             // [A] Bật lệnh Stop A
input int MaxGridLevelsStop = 10;               // [A] Số lượng lưới tối đa (mỗi chiều, tối đa 100)
input double LotSizeStop = 0.01;                // [A] Khối lượng (mức 1 - lưới gần đường gốc)
input ENUM_TP_MODE TakeProfitMode = TP_MODE_FIXED_PIPS; // [A] Chế độ TP (0=Pips cố định, 1=Theo lưới: bậc k → TP tại bậc k+1)
input double TakeProfitPipsStop = 30.0;         // [A] Take Profit (pips) - dùng khi chế độ = Pips cố định (0=off)
input bool EnableMartingaleStop = false;        // [A] Bật gấp thếp theo mức lưới (lot)
input ENUM_MARTINGALE_MODE MartingaleModeStop = MARTINGALE_MODE_MULTIPLIER; // [A] Chế độ (0=Cấp số nhân, 1=Cấp số cộng)
input double MartingaleMultiplierStop = 2.0;   // [A] Hệ số gấp - Cấp số nhân (mức 2=x2, mức 3=x4...)
input double MartingaleStepStop = 0.01;         // [A] Bước cộng - Cấp số cộng (mỗi mức cộng thêm)
input double MaxLotCap = 0;                     // [A] Giới hạn lot lớn nhất mỗi lệnh (0=không giới hạn; VD: 1 = tối đa 1 lot/lệnh)

//--- Input parameters - Cài đặt lệnh Stop B (không gấp thếp + Trading Stop)
input group "=== CÀI ĐẶT LỆNH STOP B ==="
input bool EnableStopOrdersB = false;           // [B] Bật lệnh Stop B
input int MaxGridLevelsStopB = 10;             // [B] Số lượng lưới tối đa (mỗi chiều)
input double LotSizeStopB = 0.01;               // [B] Khối lượng (cố định mọi mức)
input ENUM_TP_MODE TakeProfitModeB = TP_MODE_FIXED_PIPS; // [B] Chế độ TP (0=Pips cố định, 1=Theo lưới)
input double TakeProfitPipsStopB = 30.0;       // [B] Take Profit (pips) - khi chế độ = Pips cố định (0=off)
input bool EnableTradingStopStopB = false;      // [B] Bật gồng lãi cho từng lệnh Stop B
input double TradingStopStopBDistancePips = 10.0;  // [B] Khi giá cách entry X pips thì đặt SL dương (break-even)
input double TradingStopStopBStepPips = 5.0;   // [B] Step pips: giá đi thêm step thì dịch SL theo step

//--- Input parameters - Trading Stop, Step Tổng (Gồng lãi)
input group "=== TRADING STOP, STEP TỔNG (GỒNG LÃI) ==="
input bool EnableTradingStopStepTotal = false;                 // Bật Trading Stop, Step Tổng
input ENUM_TRADING_STOP_MODE TradingStopStepMode = TRADING_STOP_MODE_OPEN; // Chế độ gồng lãi (0=Lệnh mở, 1=Phiên, 2=Cả 2)
input double TradingStopStepTotalProfit = 50.0;                // Lãi tổng lệnh đang mở để kích hoạt (USD, 0=off)
input double TradingStopStepSessionProfit = 50.0;              // Lãi tổng phiên để kích hoạt (USD, dùng khi chế độ = Theo phiên, 0=off)
input double TradingStopStepReturnProfitOpen = 20.0;           // Hủy gồng lãi: nếu lãi lệnh mở xuống dưới X USD (chỉ khi chưa đặt SL)
input double TradingStopStepReturnProfitSession = 20.0;        // Hủy gồng lãi: nếu lãi phiên xuống dưới X USD (chỉ khi chưa đặt SL)
input double TradingStopStepPointA = 10.0;                    // Điểm A: cách lệnh dương gần nhất x pips (pips)
input double TradingStopStepSize = 5.0;                        // Step pips: giá đi thêm step thì đặt SL tại A, gồng lãi dịch SL theo step
input ENUM_TP_ACTION ActionOnTradingStopStepComplete = TP_ACTION_STOP_EA; // Hành động khi giá chạm SL (0=Dừng EA, 1=Reset EA)

//--- Input parameters - Chế độ cân bằng lệnh (reset khi đạt điều kiện → đóng hết lệnh + lệnh chờ, chờ ĐK mới)
input group "=== CHẾ ĐỘ CÂN BẰNG LỆNH ==="
input bool EnableBalanceResetMode = false;           // Bật: đạt điều kiện bên dưới thì đóng hết lệnh + lệnh chờ, chờ ĐK mới khởi động lại (ưu tiên trước gồng lãi)
input double BalanceResetTotalOpenLot = 1.0;         // Điều kiện 1: Tổng lot lệnh đang mở (không tính lệnh chờ) ≥ X (0 = không kiểm tra)
input double BalanceResetSessionProfitUSD = 50.0;    // Điều kiện 2: Lãi phiên đạt tối thiểu (USD) — ví dụ 50 = phiên đang lãi ≥ 50 USD (0 = không kiểm tra)

//--- Input parameters - Giờ hoạt động
input group "=== GIỜ HOẠT ĐỘNG ==="
input bool EnableTradingHours = false;          // Bật giờ hoạt động
input int StartHour = 0;                        // Giờ bắt đầu (0-23)
input int StartMinute = 0;                      // Phút bắt đầu (0-59)
input int EndHour = 23;                        // Giờ kết thúc (0-23)
input int EndMinute = 59;                      // Phút kết thúc (0-59)

//--- Input parameters - Dừng EA theo tích lũy lãi (sau mỗi lần reset)
input group "=== DỪNG EA THEO TÍCH LŨY LÃI ==="
input bool EnableStopEAAtAccumulatedProfit = false;  // Bật: đạt ngưỡng tích lũy lãi thì dừng EA (đóng hết lệnh, không chạy nữa)
input double StopEAAtAccumulatedProfitUSD = 0;        // Ngưỡng tích lũy lãi (USD) — tích lũy = tổng lãi sau mỗi lần reset (số dư tăng từ lúc EA bật), 0=tắt

//--- Input parameters - Dừng/Reset EA theo SL (% lỗ so với vốn)
input group "=== DỪNG/RESET EA THEO SL (% LỖ) ==="
input bool EnableStopEAAtDrawdownPercent = false;   // Bật: khi vốn (Equity) âm X% so với vốn đầu phiên thì dừng hoặc reset
input double StopEADrawdownPercent = 10.0;          // % lỗ: ví dụ 10 = khi Equity <= vốn đầu phiên × (1 - 10%) → kích hoạt
input ENUM_TP_ACTION StopEAAtDrawdownAction = TP_ACTION_STOP_EA; // Hành động: 0=Dừng EA, 1=Reset EA (đóng hết, đặt gốc mới)

//--- Input parameters - Cài đặt chung
input group "=== CÀI ĐẶT CHUNG ==="
input int MagicNumber = 123456;                 // Magic Number
input string CommentOrder = "Grid Stop V1"; // Comment cho lệnh
input bool EnableResetNotification = false;     // Bật thông báo về điện thoại khi EA reset

//--- Global variables
CTrade trade;
double pnt;
int dgt;
double basePrice;                               // Giá cơ sở để tính các level
double gridLevels[];                            // Mảng chứa các level giá cố định
int gridLevelIndex[];                           // Mảng lưu chỉ số mức lưới (1, 2, 3...)

#define MAX_GRID_LEVELS 100                     // Số mức lưới tối đa hỗ trợ mỗi chiều

// Cấu trúc lưu lot size cho mỗi mức lưới (Stop)
struct GridLotSize
{
   double lotSizeBuyStop[MAX_GRID_LEVELS];      // Lot size cho Buy Stop theo mức
   double lotSizeSellStop[MAX_GRID_LEVELS];     // Lot size cho Sell Stop theo mức
};

GridLotSize gridLotSizes;                       // Lưu trữ lot size cho mỗi mức lưới

// Biến theo dõi profit
double sessionProfit = 0.0;                     // Profit của phiên hiện tại (không dùng nữa, tính từ vốn)
double accumulatedProfit = 0.0;                 // Tích lũy = Balance hiện tại - Balance ban đầu khi EA khởi động
datetime sessionStartTime = 0;                  // Thời gian bắt đầu phiên
double initialEquity = 0.0;                     // Vốn ban đầu (Equity) khi bắt đầu phiên
double initialBalance = 0.0;                    // Số dư ban đầu (Balance) khi bắt đầu phiên
double initialBalanceAtStart = 0.0;              // Số dư ban đầu khi EA khởi động lần đầu (không reset khi EA reset)
int resetCount = 0;                              // Số lần EA reset (tích lũy lần N)
double profitStopASinceReset = 0.0;              // Lãi/lỗ Stop A kể từ lần reset gần nhất
double profitStopBSinceReset = 0.0;             // Lãi/lỗ Stop B kể từ lần reset gần nhất
double minEquity = 0.0;                        // Vốn thấp nhất (khi lỗ lớn nhất) trong phiên
double maxNegativeProfit = 0.0;                 // Số âm lớn nhất của lệnh đang mở (không reset khi EA reset)
double balanceAtMaxLoss = 0.0;                  // Số dư tại thời điểm có số âm lớn nhất (không reset khi EA reset)
double maxLotEver = 0.0;                         // Số lot lớn nhất từng có (không reset khi EA reset)
double totalLotEver = 0.0;                      // Tổng lot lớn nhất từng có (không reset khi EA reset)
bool eaStopped = false;                         // Flag dừng EA
bool eaStoppedByTradingHours = false;           // Flag dừng EA do ngoài giờ hoạt động
bool isResetting = false;                       // Flag đang trong quá trình reset

// Biến theo dõi Trading Stop, Step Tổng
bool isTradingStopActive = false;               // Flag đang ở chế độ Trading Stop
double pointA = 0.0;                            // Điểm A (SL) hiện tại cho các lệnh
double initialPointA = 0.0;                     // Điểm A ban đầu (để tính trailing)
double lastPriceForStep = 0.0;                  // Giá cuối để theo dõi step
double initialPriceForStop = 0.0;               // Giá ban đầu khi kích hoạt stop
bool firstStepDone = false;                     // Flag đã thực hiện step đầu tiên (đóng lệnh âm, set SL)
bool isTradingStopBuyDirection = false;         // Hướng của Trading Stop (true=Buy, false=Sell)

// NoPanel: không có panel - EA nhẹ chạy mượt

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   dgt = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pnt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   InitializeGridLevels();
   Print("========================================");
   Print("Grid Stop Trading EA V1 (NoPanel) đã khởi động");
   Print("Symbol: ", _Symbol);
   Print("Đường gốc (tại thời điểm EA khởi động): ", basePrice);
   Print("Lưới: chế độ ", (GridDistanceMode == GRID_MODE_FIXED ? "Cố định" : "Cấp số cộng"),
         " | Khoảng cơ sở: ", GridDistancePips, " pips");
   if(GridDistanceMode == GRID_MODE_ARITHMETIC)
      Print("  Cấp số cộng: khoảng cách lưới ", GridStepPips, " pips (bậc 1=", GridStepPips, ", bậc 2 cách bậc 1=", 2*GridStepPips, ", bậc 3 cách bậc 2=", 3*GridStepPips, " → tổng cách gốc: 1=", GridStepPips, ", 2=", (int)(GridStepPips*2*3/2), ", 3=", (int)(GridStepPips*3*4/2), " pips)");
   int maxLvl = (int)MathMax((double)MaxGridLevelsStop, (double)MaxGridLevelsStopB);
   Print("Lưới mỗi chiều: Stop A=", MaxGridLevelsStop, " | Stop B=", MaxGridLevelsStopB, " | Lưới xây max ", maxLvl, " levels");
   Print("Auto Refill: ", AutoRefillOrders ? "ON" : "OFF");
   Print("--- Lệnh Stop A: ", (EnableStopOrders ? "ON" : "OFF"), " ---");
   Print("  Lot (mức 1): ", LotSizeStop, " | TP: ", (TakeProfitMode == TP_MODE_GRID_LEVEL ? "Theo lưới" : (TakeProfitPipsStop > 0 ? StringFormat("%g pips", TakeProfitPipsStop) : "off")));
   if(EnableMartingaleStop)
   {
      if(MartingaleModeStop == MARTINGALE_MODE_ARITHMETIC)
         Print("    Gấp thếp: Cấp số cộng (+", MartingaleStepStop, ")");
      else
         Print("    Gấp thếp: Cấp số nhân (x", MartingaleMultiplierStop, ")");
   }
   if(MaxLotCap > 0)
      Print("  Giới hạn lot: ", MaxLotCap);
   Print("--- Lệnh Stop B (không gấp thếp): ", (EnableStopOrdersB ? "ON" : "OFF"), " ---");
   if(EnableStopOrdersB)
   {
      Print("  Lot: ", LotSizeStopB, " | TP: ", (TakeProfitModeB == TP_MODE_GRID_LEVEL ? "Theo lưới" : (TakeProfitPipsStopB > 0 ? StringFormat("%g pips", TakeProfitPipsStopB) : "off")));
      if(EnableTradingStopStopB)
         Print("  Trading Stop B: Khi giá cách entry ", TradingStopStopBDistancePips, " pips đặt SL, step ", TradingStopStopBStepPips, " pips (tự động bổ sung lệnh khi đạt TP)");
   }
   Print("Tổng số levels: ", ArraySize(gridLevels));
   if(EnableBalanceResetMode)
   {
      string conds = "";
      if(BalanceResetTotalOpenLot > 0) conds += "tổng lot mở >= " + DoubleToString(BalanceResetTotalOpenLot, 2);
      if(BalanceResetSessionProfitUSD > 0)
      {
         if(conds != "") conds += " và ";
         conds += "lãi phiên >= " + DoubleToString(BalanceResetSessionProfitUSD, 0) + " USD";
      }
      if(conds != "")
         Print("--- Cân bằng lệnh: ON (", conds, " → đóng hết, chờ ĐK mới) ---");
      else
         Print("--- Cân bằng lệnh: ON (chưa cấu hình điều kiện) ---");
   }
   Print("--- Trading Stop, Step Tổng ---");
   bool tradingStopEnabled = false;
   if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
   {
      tradingStopEnabled = (EnableTradingStopStepTotal && TradingStopStepTotalProfit > 0);
   }
   else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
   {
      tradingStopEnabled = (EnableTradingStopStepTotal && TradingStopStepSessionProfit > 0);
   }
   else if(TradingStopStepMode == TRADING_STOP_MODE_BOTH)
   {
      tradingStopEnabled = (EnableTradingStopStepTotal && TradingStopStepTotalProfit > 0 && TradingStopStepSessionProfit > 0);
   }
   
   if(tradingStopEnabled)
   {
      Print("Trading Stop, Step Tổng: ON");
      if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
      {
         Print("  - Chế độ: Theo lệnh mở");
         Print("  - Lãi kích hoạt (lệnh mở): ", TradingStopStepTotalProfit, " USD");
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
      {
         Print("  - Chế độ: Theo phiên");
         Print("  - Lãi kích hoạt (phiên): ", TradingStopStepSessionProfit, " USD");
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_BOTH)
      {
         Print("  - Chế độ: Tổ hợp cả 2 (ưu tiên cái đạt trước)");
         Print("  - Lãi kích hoạt (lệnh mở): ", TradingStopStepTotalProfit, " USD");
         Print("  - Lãi kích hoạt (phiên): ", TradingStopStepSessionProfit, " USD");
      }
      if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
      {
         Print("  - Lãi quay lại (lệnh mở): ", TradingStopStepReturnProfitOpen, " USD");
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
      {
         Print("  - Lãi quay lại (phiên): ", TradingStopStepReturnProfitSession, " USD");
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_BOTH)
      {
         Print("  - Lãi quay lại (lệnh mở): ", TradingStopStepReturnProfitOpen, " USD");
         Print("  - Lãi quay lại (phiên): ", TradingStopStepReturnProfitSession, " USD");
      }
      Print("  - Điểm A cách lệnh dương: ", TradingStopStepPointA, " pips");
      Print("  - Step di chuyển SL: ", TradingStopStepSize, " pips");
      Print("  - Hành động khi chạm SL: ", ActionOnTradingStopStepComplete == TP_ACTION_RESET_EA ? "Reset EA" : "Dừng EA");
   }
   else
   {
      Print("Trading Stop, Step Tổng: OFF");
   }
   if(EnableStopEAAtAccumulatedProfit && StopEAAtAccumulatedProfitUSD > 0)
      Print("--- Dừng EA theo tích lũy lãi: ON (tích lũy >= ", StopEAAtAccumulatedProfitUSD, " USD thì dừng EA, đóng hết lệnh) ---");
   if(EnableStopEAAtDrawdownPercent && StopEADrawdownPercent > 0)
      Print("--- Dừng/Reset EA theo SL % lỗ: ON (Equity âm ", StopEADrawdownPercent, "% so với vốn đầu phiên → ", (StopEAAtDrawdownAction == TP_ACTION_RESET_EA ? "Reset EA" : "Dừng EA"), ") ---");
   Print("--- Giờ hoạt động ---");
   if(EnableTradingHours)
   {
      Print("Giờ hoạt động: ON");
      Print("  - Bắt đầu: ", StartHour, ":", (StartMinute < 10 ? "0" : ""), StartMinute);
      Print("  - Kết thúc: ", EndHour, ":", (EndMinute < 10 ? "0" : ""), EndMinute);
      Print("  - Ngoài giờ: EA không vào lệnh mới, nhưng tiếp tục quản lý lệnh đang mở");
   }
   else
   {
      Print("Giờ hoạt động: OFF");
   }
   Print("========================================");
   
   // Khởi tạo phiên
   sessionStartTime = TimeCurrent();
   sessionProfit = 0.0;
   accumulatedProfit = 0.0;
   resetCount = 0;  // Khởi tạo số lần reset = 0
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);  // Lưu vốn ban đầu (Balance + Floating)
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // Lưu số dư ban đầu
   initialBalanceAtStart = AccountInfoDouble(ACCOUNT_BALANCE);  // Lưu số dư ban đầu khi EA khởi động lần đầu (không reset)
   minEquity = initialEquity;  // Khởi tạo vốn thấp nhất bằng vốn ban đầu
   maxNegativeProfit = 0.0;  // Khởi tạo số âm lớn nhất
   balanceAtMaxLoss = AccountInfoDouble(ACCOUNT_BALANCE);  // Khởi tạo số dư tại thời điểm lỗ lớn nhất
   maxLotEver = 0.0;  // Khởi tạo số lot lớn nhất từng có
   totalLotEver = 0.0;  // Khởi tạo tổng lot lớn nhất từng có
   
   Print("Vốn ban đầu phiên: ", initialEquity, " USD");
   
   // NoPanel: không tạo panel
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // NoPanel: không cần xóa panel
   Print("Grid Stop Trading EA V1 (NoPanel) đã dừng. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // NoPanel: không cập nhật panel
   
   // Kiểm tra giờ hoạt động trước (để tự động khởi động lại nếu cần)
   bool withinTradingHours = IsWithinTradingHours();
   
   // Nếu trong giờ hoạt động và EA đang TẮT do giờ hoạt động → tự động khởi động lại
   // CHỈ khởi động lại khi EA đang TẮT (dừng do ngoài giờ). EA đang hoạt động thì tiếp tục, KHÔNG khởi động lại
   // Điều kiện: EA đang tắt (eaStoppedByTradingHours) VÀ không có lệnh đang mở (đảm bảo EA thực sự đang tắt)
   if(EnableTradingHours && withinTradingHours && eaStoppedByTradingHours && !eaStopped && !HasOpenOrders())
   {
      eaStoppedByTradingHours = false;
      Print("========================================");
      Print("✓ VÀO GIỜ HOẠT ĐỘNG - EA ĐANG TẮT → TỰ ĐỘNG KHỞI ĐỘNG LẠI");
      basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      InitializeGridLevels();
      ZeroMemory(gridLotSizes);
      Print("Giá cơ sở mới: ", basePrice);
      Print("EA sẽ bắt đầu đặt lệnh tại các mức lưới mới");
      Print("========================================");
   }
   else if(EnableTradingHours && withinTradingHours && eaStoppedByTradingHours && !eaStopped && HasOpenOrders())
   {
      // EA đang tắt do giờ nhưng vẫn còn lệnh (bất thường) → chỉ reset flag, KHÔNG khởi động lại, tiếp tục quản lý lệnh
      eaStoppedByTradingHours = false;
   }
   
   // Nếu EA đã dừng (do TP/SL hoặc lý do khác) thì không làm gì
   // LƯU Ý: EA dừng do TP/SL sẽ KHÔNG tự động khởi động lại, kể cả khi vào giờ hoạt động
   if(eaStopped)
   {
      // Log mỗi 1000 tick để xác nhận EA đã dừng
      static int stoppedTickCount = 0;
      stoppedTickCount++;
      if(stoppedTickCount % 1000 == 0)
      {
         Print("EA đã DỪNG (do đạt TP/SL hoặc lý do khác) - Không tự động khởi động lại");
         if(EnableTradingHours && withinTradingHours)
         {
            Print("  → Lưu ý: EA đang trong giờ hoạt động nhưng vẫn DỪNG vì đã đạt TP/SL");
         }
      }
      return;
   }
   
   // Nếu EA đã dừng thì không quản lý lệnh
   if(eaStopped)
   {
      static int firstStopLog = 0;
      if(firstStopLog == 0)
      {
         Print("========================================");
         Print("EA đã DỪNG - Không quản lý lệnh nữa");
         Print("========================================");
         firstStopLog = 1;
      }
      return;
   }
   
   // Dừng/Reset EA theo SL (% lỗ so với vốn): Khi Equity âm X% so với vốn đầu phiên
   if(EnableStopEAAtDrawdownPercent && StopEADrawdownPercent > 0 && initialEquity > 0 && basePrice > 0)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double thresholdEquity = initialEquity * (1.0 - StopEADrawdownPercent / 100.0);
      if(currentEquity <= thresholdEquity)
      {
         double drawdownPct = (initialEquity - currentEquity) / initialEquity * 100.0;
         double accumulatedBefore = accumulatedProfit;
         string slReason = (StopEAAtDrawdownAction == TP_ACTION_STOP_EA) ? "SL % lỗ - Dừng EA" : "SL % lỗ - Reset EA";
         Print("========================================");
         Print("=== SL % LỖ KÍCH HOẠT: Vốn âm ", DoubleToString(drawdownPct, 1), "% (", currentEquity, " / ", initialEquity, ") ===");
         if(StopEAAtDrawdownAction == TP_ACTION_STOP_EA)
         {
            CloseAllPendingOrders();
            CloseAllOpenPositions();
            Sleep(200);
            double accumulatedAfter = AccountInfoDouble(ACCOUNT_BALANCE) - initialBalanceAtStart;
            double profitThisTime = accumulatedAfter - accumulatedBefore;
            if(EnableResetNotification)
               SendResetNotification(slReason, accumulatedBefore, profitThisTime, accumulatedAfter, resetCount);
            eaStopped = true;
            eaStoppedByTradingHours = false;
            Print("Hành động: DỪNG EA");
         }
         else
         {
            isResetting = true;
            BalanceResetAndWaitForNewBase();
            isResetting = false;
            double accumulatedAfter = AccountInfoDouble(ACCOUNT_BALANCE) - initialBalanceAtStart;
            double profitThisTime = accumulatedAfter - accumulatedBefore;
            if(EnableResetNotification)
               SendResetNotification(slReason, accumulatedBefore, profitThisTime, accumulatedAfter, resetCount + 1);
            Print("Hành động: RESET EA (đóng hết, đặt gốc mới)");
         }
         Print("========================================");
         return;
      }
   }
   
   // Chế độ cân bằng: ưu tiên trước gồng lãi — đạt ngưỡng thì reset luôn, không kích hoạt gồng lãi
   if(EnableBalanceResetMode && basePrice > 0 && !isTradingStopActive)
   {
      double sessionPr = AccountInfoDouble(ACCOUNT_EQUITY) - initialEquity;
      double totalOpenLot = GetTotalLot();
      bool cond1 = (BalanceResetTotalOpenLot <= 0) || (totalOpenLot >= BalanceResetTotalOpenLot);
      bool cond2 = (BalanceResetSessionProfitUSD <= 0) || (sessionPr >= BalanceResetSessionProfitUSD);
      bool hasAnyCond = (BalanceResetTotalOpenLot > 0) || (BalanceResetSessionProfitUSD > 0);
      if(hasAnyCond && cond1 && cond2)
      {
         Print("Cân bằng (ưu tiên trước gồng lãi): Tổng lot mở ", totalOpenLot, " | Lãi phiên ", sessionPr, " USD → Đóng hết, chờ ĐK mới.");
         BalanceResetAndWaitForNewBase();
         return;
      }
   }
   
   // Kiểm tra Trading Stop, Step Tổng
   if(!isTradingStopActive)
   {
      if(EnableTradingStopStepTotal)
         CheckTradingStopStepTotal();
   }
   else
   {
      ManageTradingStop();
   }
   
   // Kiểm tra giờ hoạt động
   bool hasOpenOrders = HasOpenOrders();
   
   // Logic: Nếu trong thời gian hoạt động HOẶC có lệnh đang mở thì cho phép chạy
   if(withinTradingHours || hasOpenOrders)
   {
      // Reset flag dừng do giờ hoạt động nếu đang trong giờ hoạt động hoặc có lệnh đang mở
      if((withinTradingHours || hasOpenOrders) && eaStoppedByTradingHours)
      {
         eaStoppedByTradingHours = false;
         if(hasOpenOrders && !withinTradingHours)
         {
            // Có lệnh đang mở nhưng ngoài giờ → EA vẫn tiếp tục chạy để quản lý lệnh
            static int firstLogAfterHours = 0;
            if(firstLogAfterHours == 0)
            {
               Print("========================================");
               Print("✓ EA VẪN CÒN LỆNH ĐANG MỞ - TIẾP TỤC HOẠT ĐỘNG");
               Print("EA sẽ tiếp tục quản lý lệnh cho đến khi reset tự động và không còn lệnh");
               Print("========================================");
               firstLogAfterHours = 1;
            }
         }
      }
      
      // Quản lý lệnh khi không ở chế độ Trading Stop
      if(!isTradingStopActive)
      {
         static int s_gridTickCount = 0;
         s_gridTickCount++;
         if(s_gridTickCount % 3 == 0)
            ManageGridOrders();
         if(EnableTradingStopStopB && EnableStopOrdersB && TradingStopStopBDistancePips > 0)
            ManageTradingStopStopB();
      }
   }
   else
   {
      // Ngoài thời gian hoạt động và không có lệnh đang mở
      // Đánh dấu EA dừng do giờ hoạt động (nhưng không set eaStopped = true để có thể tự động khởi động lại)
      if(!eaStoppedByTradingHours)
      {
         eaStoppedByTradingHours = true;
         Print("========================================");
         Print("⏳ NGOÀI GIỜ HOẠT ĐỘNG - EA TẠM DỪNG");
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         Print("Giờ hiện tại: ", dt.hour, ":", (dt.min < 10 ? "0" : ""), dt.min);
         Print("Giờ bắt đầu: ", StartHour, ":", (StartMinute < 10 ? "0" : ""), StartMinute);
         Print("Giờ kết thúc: ", EndHour, ":", (EndMinute < 10 ? "0" : ""), EndMinute);
         Print("EA sẽ tự động khởi động lại khi vào giờ hoạt động");
         Print("========================================");
      }
      
      // Log mỗi 1000 tick để thông báo đang chờ giờ hoạt động
      static int waitHoursTickCount = 0;
      waitHoursTickCount++;
      if(waitHoursTickCount % 1000 == 0)
      {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         Print("⏳ Ngoài giờ hoạt động - EA đang chờ. Giờ hiện tại: ", dt.hour, ":", (dt.min < 10 ? "0" : ""), dt.min, " | Giờ bắt đầu: ", StartHour, ":", (StartMinute < 10 ? "0" : ""), StartMinute, " | Giờ kết thúc: ", EndHour, ":", (EndMinute < 10 ? "0" : ""), EndMinute);
      }
   }
   
   // Cập nhật thông tin theo dõi (mỗi 10 tick để giảm tải)
   static int tickCount = 0;
   tickCount++;
   if(tickCount % 10 == 0)
   {
      UpdateTrackingInfo();
      // Cập nhật tích lũy = Balance hiện tại - Balance ban đầu
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      accumulatedProfit = currentBalance - initialBalanceAtStart;
   }
}

//+------------------------------------------------------------------+
//| Tính tổng profit của các lệnh đang mở (floating profit/loss)    |
//+------------------------------------------------------------------+
double GetTotalOpenProfit()
{
   double totalProfit = 0.0;
   
   // Duyệt qua tất cả positions đang mở
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            // Cộng profit và swap của mỗi position (có thể dương hoặc âm)
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Tính tổng lãi của lệnh Buy ĐANG MỞ (cả dương và âm)            |
//+------------------------------------------------------------------+
double GetBuyProfitTotal()
{
   double totalBuyProfit = 0.0;
   
   // Duyệt qua tất cả positions đang mở
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double positionProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            
            // Tính TẤT CẢ lệnh Buy (cả dương và âm)
            if(posType == POSITION_TYPE_BUY)
            {
               totalBuyProfit += positionProfit;
            }
         }
      }
   }
   
   return totalBuyProfit;
}

//+------------------------------------------------------------------+
//| Tính tổng lãi của lệnh Sell ĐANG MỞ (cả dương và âm)            |
//+------------------------------------------------------------------+
double GetSellProfitTotal()
{
   double totalSellProfit = 0.0;
   
   // Duyệt qua tất cả positions đang mở
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double positionProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            
            // Tính TẤT CẢ lệnh Sell (cả dương và âm)
            if(posType == POSITION_TYPE_SELL)
            {
               totalSellProfit += positionProfit;
            }
         }
      }
   }
   
   return totalSellProfit;
}

//+------------------------------------------------------------------+
//| Đếm số lệnh Buy đang mở (symbol + magic)                         |
//+------------------------------------------------------------------+
int CountBuyPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Đếm số lệnh Sell đang mở (symbol + magic)                        |
//+------------------------------------------------------------------+
int CountSellPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Lấy thống kê position một lần duyệt (giảm tải, dùng trong hot path) |
//+------------------------------------------------------------------+
void GetPositionStats(int &outBuyCount, int &outSellCount, double &outBuyProfit, double &outSellProfit, double &outTotalProfit)
{
   outBuyCount = 0;
   outSellCount = 0;
   outBuyProfit = 0.0;
   outSellProfit = 0.0;
   outTotalProfit = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      outTotalProfit += profit;
      if(posType == POSITION_TYPE_BUY)
      {
         outBuyCount++;
         outBuyProfit += profit;
      }
      else
      {
         outSellCount++;
         outSellProfit += profit;
      }
   }
}

//+------------------------------------------------------------------+
//| Đếm số position Buy/Sell theo comment (A hoặc B)                  |
//+------------------------------------------------------------------+
void GetPositionStatsByComment(string commentSuffix, int &outBuyCount, int &outSellCount)
{
   outBuyCount = 0;
   outSellCount = 0;
   string fullComment = CommentOrder + commentSuffix;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetString(POSITION_COMMENT) != fullComment)
         continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
         outBuyCount++;
      else
         outSellCount++;
   }
}

//+------------------------------------------------------------------+
//| Reset EA - Khởi động lại tại giá mới                             |
//+------------------------------------------------------------------+
void ResetEA(string resetReason = "Thủ công")
{
   Print("=== RESET EA ===");
   Print("Lý do reset: ", resetReason);
   
   // Đánh dấu đang trong quá trình reset
   isResetting = true;
   
   // Tính profit của phiên hiện tại
   // Profit phiên = Vốn hiện tại - Vốn ban đầu (lãi)
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double totalSessionProfit = currentEquity - initialEquity;
   
   // Tính tích lũy = Balance hiện tại - Balance ban đầu khi EA khởi động lần đầu
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accumulatedProfitBefore = accumulatedProfit; // Lưu tích lũy trước reset
   accumulatedProfit = currentBalance - initialBalanceAtStart; // Tích lũy = số dư tăng lên từ khi EA khởi động
   double profitThisReset = accumulatedProfit - accumulatedProfitBefore; // Profit của lần reset này
   
   Print("Profit phiên trước reset: ", totalSessionProfit, " USD");
   Print("  - Vốn ban đầu: ", initialEquity, " USD");
   Print("  - Vốn hiện tại: ", currentEquity, " USD");
   Print("  - Số dư ban đầu (khi EA khởi động): ", initialBalanceAtStart, " USD");
   Print("  - Số dư hiện tại: ", currentBalance, " USD");
   // Tăng số lần reset
   resetCount++;
   
   Print("Tích lũy trước reset: ", accumulatedProfitBefore, " USD");
   Print("Tích lũy mới (số dư tăng): ", accumulatedProfit, " USD");
   Print("Profit lần reset này: ", profitThisReset, " USD");
   Print("Số lần tích lũy: ", resetCount);
   
   // Đóng tất cả pending orders
   CloseAllPendingOrders();
   
   // Đóng tất cả positions đang mở
   CloseAllOpenPositions();
   
   // Đợi ngắn để các lệnh đóng hoàn tất (giảm từ 500ms để EA mượt hơn)
   Sleep(200);
   
   // Cập nhật tích lũy lãi sau khi đóng hết (số dư đã cập nhật)
   accumulatedProfit = AccountInfoDouble(ACCOUNT_BALANCE) - initialBalanceAtStart;
   if(EnableStopEAAtAccumulatedProfit && StopEAAtAccumulatedProfitUSD > 0 && accumulatedProfit >= StopEAAtAccumulatedProfitUSD)
   {
      Print("========================================");
      Print("Đạt ngưỡng tích lũy lãi: ", accumulatedProfit, " USD >= ", StopEAAtAccumulatedProfitUSD, " USD → DỪNG EA (không lệnh mở, không lệnh chờ).");
      Print("========================================");
      eaStopped = true;
      isResetting = false;
      return;
   }
   
   // Tắt flag reset
   isResetting = false;
   
   // Reset basePrice tại giá mới
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Reset grid levels
   InitializeGridLevels();
   
   // Reset lot sizes đã lưu
   ZeroMemory(gridLotSizes);
   
   // Reset phiên về 0 và cập nhật vốn ban đầu mới
   sessionProfit = 0.0;
   profitStopASinceReset = 0.0;
   profitStopBSinceReset = 0.0;
   sessionStartTime = TimeCurrent();
   
   // Cập nhật vốn ban đầu mới (sau khi đóng tất cả lệnh)
   double oldInitialEquity = initialEquity;
   double oldInitialBalance = initialBalance;
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);  // Vốn mới khi EA khởi động lại
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // Số dư mới khi EA khởi động lại
   minEquity = initialEquity;  // Reset vốn thấp nhất về vốn ban đầu mới
   // KHÔNG reset maxNegativeProfit và balanceAtMaxLoss - giữ lại để theo dõi lịch sử
   // KHÔNG reset maxLotEver và totalLotEver - giữ lại để theo dõi lịch sử
   
   // Đảm bảo EA tiếp tục hoạt động sau khi reset
   eaStopped = false;
   
   // Kiểm tra giờ hoạt động sau khi reset
   // Nếu ngoài giờ hoạt động và không còn lệnh nào → dừng do giờ hoạt động
   bool withinTradingHoursAfterReset = IsWithinTradingHours();
   bool hasOpenOrdersAfterReset = HasOpenOrders();
   
   if(EnableTradingHours && !withinTradingHoursAfterReset && !hasOpenOrdersAfterReset)
   {
      // Ngoài giờ hoạt động và không có lệnh → dừng do giờ hoạt động
      eaStoppedByTradingHours = true;
      Print("========================================");
      Print("⏳ SAU KHI RESET - NGOÀI GIỜ HOẠT ĐỘNG VÀ KHÔNG CÓ LỆNH");
      Print("EA sẽ tạm dừng và tự động khởi động lại khi vào giờ hoạt động");
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      Print("Giờ hiện tại: ", dt.hour, ":", (dt.min < 10 ? "0" : ""), dt.min);
      Print("Giờ bắt đầu: ", StartHour, ":", (StartMinute < 10 ? "0" : ""), StartMinute);
      Print("Giờ kết thúc: ", EndHour, ":", (EndMinute < 10 ? "0" : ""), EndMinute);
      Print("========================================");
   }
   else
   {
      // Trong giờ hoạt động hoặc có lệnh đang mở → tiếp tục chạy
      eaStoppedByTradingHours = false;
   }
   
   // Reset biến Trading Stop
   isTradingStopActive = false;
   pointA = 0.0;
   initialPointA = 0.0;
   lastPriceForStep = 0.0;
   initialPriceForStop = 0.0;
   firstStepDone = false;
   
   
   Print("EA đã reset tại giá mới: ", basePrice);
   Print("--- Reset phiên ---");
   Print("  - Vốn ban đầu cũ: ", oldInitialEquity, " USD");
   Print("  - Vốn ban đầu mới: ", initialEquity, " USD");
   Print("  - Tổng phiên đã reset về: 0 USD");
   Print("Phiên mới đã bắt đầu - Tổng phiên sẽ tính lại từ vốn ban đầu mới");
   
   // Gửi thông báo về điện thoại nếu được bật
   if(EnableResetNotification)
   {
      SendResetNotification(resetReason, accumulatedProfitBefore, profitThisReset, accumulatedProfit, resetCount);
   }
}

//+------------------------------------------------------------------+
//| Dừng EA - Đóng tất cả lệnh và xóa pending orders                |
//+------------------------------------------------------------------+
void StopEA()
{
   Print("========================================");
   Print("=== DỪNG EA ===");
   Print("Đang đóng tất cả lệnh...");
   
   // Đóng tất cả pending orders
   int pendingCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            if(trade.OrderDelete(ticket))
               pendingCount++;
         }
      }
   }
   Print("Đã xóa ", pendingCount, " pending orders");
   
   // Đóng tất cả positions đang mở
   int positionCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            if(trade.PositionClose(ticket))
               positionCount++;
         }
      }
   }
   Print("Đã đóng ", positionCount, " positions");
   
   // Set flag dừng EA (dừng do TP/SL hoặc lý do khác, không phải do giờ hoạt động)
   // LƯU Ý: EA dừng do TP/SL sẽ KHÔNG tự động khởi động lại, kể cả khi vào giờ hoạt động
   eaStopped = true;
   eaStoppedByTradingHours = false; // Reset flag dừng do giờ hoạt động vì đây là dừng vĩnh viễn
   
   Print("EA đã DỪNG - Không quản lý lệnh nữa");
   Print("Lưu ý: EA dừng do đạt TP/SL sẽ KHÔNG tự động khởi động lại");
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Đóng tất cả positions đang mở                                    |
//+------------------------------------------------------------------+
void CloseAllOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tính profit/loss của position đã đóng (realized profit/loss)     |
//+------------------------------------------------------------------+
double CalculateClosedPositionProfit(ulong positionId)
{
   double totalProfit = 0.0;
   
   if(HistorySelectByPosition(positionId))
   {
      int totalDeals = HistoryDealsTotal();
      
      for(int i = 0; i < totalDeals; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket > 0)
         {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            
            if(dealMagic == MagicNumber && dealSymbol == _Symbol)
            {
               totalProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               totalProfit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
               totalProfit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            }
         }
      }
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Đóng tất cả pending orders                                       |
//+------------------------------------------------------------------+
void CloseAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tổng lot lệnh mở đang âm dưới đường gốc (open < base, profit+swap < 0) |
//+------------------------------------------------------------------+
double GetTotalNegativeLotBelowBase()
{
   double total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(openPrice >= basePrice) continue;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pr < 0)
         total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Tổng lot lệnh mở đang âm trên đường gốc (open > base, profit+swap < 0) |
//+------------------------------------------------------------------+
double GetTotalNegativeLotAboveBase()
{
   double total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(t <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(openPrice <= basePrice) continue;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pr < 0)
         total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Cân bằng: đóng hết lệnh mở + lệnh chờ, chờ điều kiện mới đặt gốc  |
//+------------------------------------------------------------------+
void BalanceResetAndWaitForNewBase()
{
   Print("========================================");
   Print("=== CÂN BẰNG LỆNH - RESET CHỜ ĐK MỚI ===");
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double sessionPr = currentEquity - initialEquity;
   Print("Lãi phiên: ", sessionPr, " USD | Đóng toàn bộ lệnh mở và lệnh chờ.");
   CloseAllPendingOrders();
   CloseAllOpenPositions();
   Sleep(200);
   accumulatedProfit = AccountInfoDouble(ACCOUNT_BALANCE) - initialBalanceAtStart;
   if(EnableStopEAAtAccumulatedProfit && StopEAAtAccumulatedProfitUSD > 0 && accumulatedProfit >= StopEAAtAccumulatedProfitUSD)
   {
      Print("========================================");
      Print("Đạt ngưỡng tích lũy lãi: ", accumulatedProfit, " USD >= ", StopEAAtAccumulatedProfitUSD, " USD → DỪNG EA (không lệnh mở, không lệnh chờ).");
      Print("========================================");
      eaStopped = true;
      initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      isTradingStopActive = false;
      pointA = 0.0;
      initialPointA = 0.0;
      lastPriceForStep = 0.0;
      initialPriceForStop = 0.0;
      firstStepDone = false;
      return;
   }
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   isTradingStopActive = false;
   pointA = 0.0;
   initialPointA = 0.0;
   lastPriceForStep = 0.0;
   initialPriceForStop = 0.0;
   firstStepDone = false;
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   InitializeGridLevels();
   Print("Đã đặt đường gốc mới: ", basePrice, " → khởi động lại.");
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
   // Chỉ xử lý khi position đóng
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // Kiểm tra xem có phải position đóng do TP không
      if(HistoryDealSelect(trans.deal))
      {
         long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
         
         // Xử lý khi position đóng do TP hoặc SL
         if(reason == DEAL_REASON_TP || reason == DEAL_REASON_SL || reason == DEAL_REASON_SO)
         {
            // Lấy thông tin position đã đóng
            long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
            
            if(magic == MagicNumber && symbol == _Symbol)
            {
               // Lấy Position ID từ deal
               ulong positionId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
               
               // Tính profit của position đã đóng (có thể lãi hoặc lỗ)
               double positionProfit = CalculateClosedPositionProfit(positionId);
               
               // Lấy comment từ position (deal mở) để phân biệt Stop A / Stop B
               string posComment = "";
               if(HistorySelectByPosition(positionId))
               {
                  for(int k = 0; k < HistoryDealsTotal(); k++)
                  {
                     ulong dt = HistoryDealGetTicket(k);
                     if(dt > 0 && (HistoryDealGetInteger(dt, DEAL_TYPE) == DEAL_TYPE_BUY || HistoryDealGetInteger(dt, DEAL_TYPE) == DEAL_TYPE_SELL))
                     {
                        posComment = HistoryDealGetString(dt, DEAL_COMMENT);
                        break;
                     }
                  }
               }
               if(StringFind(posComment, " A") >= 0)
                  profitStopASinceReset += positionProfit;
               else if(StringFind(posComment, " B") >= 0)
                  profitStopBSinceReset += positionProfit;
               
               // Nếu đang trong quá trình reset, không cộng vào sessionProfit
               if(!isResetting)
                  sessionProfit += positionProfit;
               
               Print("Position đóng - Lý do: ", reason == DEAL_REASON_TP ? "TP" : (reason == DEAL_REASON_SL ? "SL" : "SO"), 
                     " | Profit: ", positionProfit, " USD | A: ", profitStopASinceReset, " B: ", profitStopBSinceReset);
            }
         }
         
         // Chỉ xử lý logic bổ sung lệnh khi đạt TP
         if(reason == DEAL_REASON_TP)
         {
            // Lấy thông tin position đã đóng
            long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
            
            if(magic == MagicNumber && symbol == _Symbol)
            {
               // Lấy Position ID từ deal
               ulong positionId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
               
               // Lấy thông tin position từ History
               if(HistorySelectByPosition(positionId))
               {
                  int totalDeals = HistoryDealsTotal();
                  double lotSize = 0;
                  double priceOpen = 0;
                  ENUM_ORDER_TYPE orderType = WRONG_VALUE;
                  
                  string dealComment = "";
                  for(int i = 0; i < totalDeals; i++)
                  {
                     ulong dealTicket = HistoryDealGetTicket(i);
                     if(dealTicket > 0)
                     {
                        long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                        if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
                        {
                           lotSize = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                           priceOpen = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                           dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                           if(dealType == DEAL_TYPE_BUY)
                              orderType = ORDER_TYPE_BUY_STOP;
                           else
                              orderType = ORDER_TYPE_SELL_STOP;
                           break;
                        }
                     }
                  }
                  
                  if(orderType != WRONG_VALUE && priceOpen > 0 && lotSize > 0)
                  {
                     int levelNumber = GetGridLevelNumber(priceOpen);
                     if(levelNumber > 0)
                     {
                        bool isStopA = (StringFind(dealComment, " A") >= 0);
                        if(isStopA)
                           SaveLotSizeForLevel(orderType, levelNumber, lotSize);
                        
                        Print("✓ Position đạt TP - ", (isStopA ? "A" : "B"), " Mức ", levelNumber, " | ", EnumToString(orderType), " | Lot: ", lotSize, " | Giá mở: ", priceOpen);
                        
                        if(AutoRefillOrders)
                        {
                           int refillBuyCnt = 0, refillSellCnt = 0;
                           if(isStopA && EnableStopOrders)
                           {
                              GetPositionStatsByComment(" A", refillBuyCnt, refillSellCnt);
                              bool allowRefill = (orderType == ORDER_TYPE_BUY_STOP && refillBuyCnt < MaxOpenForStopRefill) ||
                                                 (orderType == ORDER_TYPE_SELL_STOP && refillSellCnt < MaxOpenForStopRefill);
                              if(allowRefill)
                              {
                                 Sleep(50);
                                 double levelPrice = GetLevelPrice(levelNumber, orderType);
                                 if(levelPrice > 0)
                                    EnsureOrderAtLevel(orderType, levelPrice, levelNumber, true);
                              }
                           }
                           else if(!isStopA && EnableStopOrdersB)
                           {
                              GetPositionStatsByComment(" B", refillBuyCnt, refillSellCnt);
                              bool allowRefill = (orderType == ORDER_TYPE_BUY_STOP && refillBuyCnt < MaxOpenForStopRefill) ||
                                                 (orderType == ORDER_TYPE_SELL_STOP && refillSellCnt < MaxOpenForStopRefill);
                              if(allowRefill)
                              {
                                 Sleep(50);
                                 double levelPrice = GetLevelPrice(levelNumber, orderType);
                                 if(levelPrice > 0)
                                    EnsureOrderAtLevel(orderType, levelPrice, levelNumber, false);
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tính khoảng cách từ đường gốc (pips) cho bậc lưới i (1,2,3...)  |
//| FIXED: i*x | ARITHMETIC: step*(1+2+...+i) = step*i*(i+1)/2       |
//|   (khoảng cách lưới cố định = step; bậc 2 cách bậc 1 = step+step; bậc 3 cách bậc 2 = step+step+step) |
//+------------------------------------------------------------------+
double GetGridDistancePipsForLevel(int levelNumber)
{
   if(levelNumber < 1) return 0;
   double distPips = GridDistancePips;
   if(GridDistanceMode == GRID_MODE_FIXED)
      distPips = levelNumber * GridDistancePips;
   else if(GridDistanceMode == GRID_MODE_ARITHMETIC)
      // Bậc 1 cách gốc = step; bậc 2 cách bậc 1 = step+step → tổng cách gốc = step+2*step; bậc 3 thêm step+step+step...
      // Tổng cách gốc bậc n = step*(1+2+...+n) = step*n*(n+1)/2
      distPips = GridStepPips * (levelNumber * (levelNumber + 1) / 2.0);
   return distPips;
}

//+------------------------------------------------------------------+
//| Khởi tạo các level giá cố định cho lưới                        |
//+------------------------------------------------------------------+
void InitializeGridLevels()
{
   int maxLevelA = (int)MathMin((double)MaxGridLevelsStop, (double)MAX_GRID_LEVELS);
   int maxLevelB = (int)MathMin((double)MaxGridLevelsStopB, (double)MAX_GRID_LEVELS);
   int maxLevel = (int)MathMax((double)maxLevelA, (double)maxLevelB);
   if(maxLevel > MAX_GRID_LEVELS)
   {
      maxLevel = MAX_GRID_LEVELS;
      Print("⚠ Max levels (A/B) vượt giới hạn - Sử dụng ", maxLevel);
   }
   int totalLevels = maxLevel * 2 + 1; // Cả 2 phía + giá cơ sở
   
   ArrayResize(gridLevels, totalLevels);
   ArrayResize(gridLevelIndex, totalLevels);
   
   int index = 0;
   
   // Level phía trên giá cơ sở (mức 1 là gần nhất, maxLevel là xa nhất)
   for(int i = 1; i <= maxLevel; i++)
   {
      double distPips = GetGridDistancePipsForLevel(i);
      double distPrice = distPips * pnt * 10.0;
      gridLevels[index] = NormalizeDouble(basePrice + distPrice, dgt);
      gridLevelIndex[index] = i;
      index++;
   }
   
   // Level giá cơ sở (không đặt lệnh, giữ để tương thích)
   gridLevels[index] = NormalizeDouble(basePrice, dgt);
   gridLevelIndex[index] = 0;
   index++;
   
   // Level phía dưới giá cơ sở (mức 1 là gần nhất, maxLevel là xa nhất)
   for(int i = 1; i <= maxLevel; i++)
   {
      double distPips = GetGridDistancePipsForLevel(i);
      double distPrice = distPips * pnt * 10.0;
      gridLevels[index] = NormalizeDouble(basePrice - distPrice, dgt);
      gridLevelIndex[index] = i;
      index++;
   }
   
   string modeStr = (GridDistanceMode == GRID_MODE_FIXED) ? "Cố định" : "Cấp số cộng";
   Print("Đã khởi tạo ", totalLevels, " grid levels (max level = ", maxLevel, ", chế độ: ", modeStr, ")");
   Print("  → Stop A đặt lệnh tại level 1..", MaxGridLevelsStop, " | Stop B đặt lệnh tại level 1..", MaxGridLevelsStopB);
}

//+------------------------------------------------------------------+
//| Quản lý hệ thống lưới                                           |
//+------------------------------------------------------------------+
void ManageGridOrders()
{
   // Nếu EA đã dừng thì không quản lý lệnh
   if(eaStopped)
      return;
   
   // Nếu EA đang dừng do giờ hoạt động và không có lệnh đang mở thì không đặt lệnh mới
   // LƯU Ý: Nếu có lệnh đang mở thì EA vẫn tiếp tục quản lý lệnh, kể cả khi ngoài giờ hoạt động
   if(EnableTradingHours && eaStoppedByTradingHours && !HasOpenOrders())
      return;
   
   // Nếu đang ở chế độ Trading Stop thì không đặt lệnh mới
   if(isTradingStopActive)
      return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int buyCntA = 0, sellCntA = 0, buyCntB = 0, sellCntB = 0;
   GetPositionStatsByComment(" A", buyCntA, sellCntA);
   GetPositionStatsByComment(" B", buyCntB, sellCntB);
   bool canAddBuyStopA = (buyCntA < MaxOpenForStopRefill);
   bool canAddSellStopA = (sellCntA < MaxOpenForStopRefill);
   bool canAddBuyStopB = (buyCntB < MaxOpenForStopRefill);
   bool canAddSellStopB = (sellCntB < MaxOpenForStopRefill);
   
   double minDistance = GridDistancePips * pnt * 5.0;
   for(int i = 0; i < ArraySize(gridLevels); i++)
   {
      double level = gridLevels[i];
      if(MathAbs(level - currentPrice) < minDistance)
         continue;
      int levelNumber = gridLevelIndex[i];
      
      if(level > basePrice)
      {
         if(EnableStopOrders && canAddBuyStopA && levelNumber >= 1 && levelNumber <= MaxGridLevelsStop)
            EnsureOrderAtLevel(ORDER_TYPE_BUY_STOP, level, levelNumber, true);
         if(EnableStopOrdersB && canAddBuyStopB && levelNumber >= 1 && levelNumber <= MaxGridLevelsStopB)
            EnsureOrderAtLevel(ORDER_TYPE_BUY_STOP, level, levelNumber, false);
      }
      else if(level < basePrice)
      {
         if(EnableStopOrders && canAddSellStopA && levelNumber >= 1 && levelNumber <= MaxGridLevelsStop)
            EnsureOrderAtLevel(ORDER_TYPE_SELL_STOP, level, levelNumber, true);
         if(EnableStopOrdersB && canAddSellStopB && levelNumber >= 1 && levelNumber <= MaxGridLevelsStopB)
            EnsureOrderAtLevel(ORDER_TYPE_SELL_STOP, level, levelNumber, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Đảm bảo có lệnh tại level - tạo nếu chưa có (isStopA = Stop A, false = Stop B) |
//+------------------------------------------------------------------+
void EnsureOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, int levelNumber, bool isStopA)
{
   if(eaStopped)
      return;
   if(isTradingStopActive)
      return;
   if(OrderOrPositionExistsAtLevel(orderType, priceLevel, isStopA))
      return;
   if(!CanPlaceOrderAtLevel(orderType, priceLevel))
      return;
   PlacePendingOrder(orderType, priceLevel, levelNumber, isStopA);
}

//+------------------------------------------------------------------+
//| Kiểm tra có lệnh hoặc position tại level không (theo Stop A hoặc B) |
//+------------------------------------------------------------------+
bool OrderOrPositionExistsAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, bool isStopA)
{
   double tolerance = GridDistancePips * pnt * 5.0;
   bool isBuyDirection = (orderType == ORDER_TYPE_BUY_STOP);
   string fullComment = CommentOrder + (isStopA ? " A" : " B");
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol &&
            OrderGetString(ORDER_COMMENT) == fullComment)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(orderPrice - priceLevel) < tolerance)
            {
               ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               if(ot == orderType)
                  return true;
            }
         }
      }
   }
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetString(POSITION_COMMENT) == fullComment)
         {
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(posPrice - priceLevel) < tolerance)
            {
               ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               bool isPosBuy = (pt == POSITION_TYPE_BUY);
               if(isBuyDirection == isPosBuy)
                  return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Kiểm tra xem có trong thời gian hoạt động không (cache 1 giây)  |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   if(!EnableTradingHours)
      return true; // Nếu không bật giờ hoạt động thì luôn cho phép
   static datetime s_lastCheck = 0;
   static bool s_cachedResult = true;
   datetime now = TimeCurrent();
   if(now != s_lastCheck)
   {
      s_lastCheck = now;
      MqlDateTime dt;
      TimeToStruct(now, dt);
      int currentMinutes = dt.hour * 60 + dt.min;
      int startMinutes = StartHour * 60 + StartMinute;
      int endMinutes = EndHour * 60 + EndMinute;
      if(endMinutes < startMinutes)
         s_cachedResult = (currentMinutes >= startMinutes || currentMinutes <= endMinutes);
      else
         s_cachedResult = (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
   }
   return s_cachedResult;
}

//+------------------------------------------------------------------+
//| Kiểm tra xem có lệnh đang mở không (positions hoặc pending orders) |
//+------------------------------------------------------------------+
bool HasOpenOrders()
{
   // Kiểm tra positions đang mở
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }
   
   // Kiểm tra pending orders
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Kiểm tra có thể đặt lệnh tại level không (cân bằng lưới)       |
//+------------------------------------------------------------------+
bool CanPlaceOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel)
{
   double tolerance = GridDistancePips * pnt * 5.0;
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY_STOP);
   
   int buyCount = 0;
   int sellCount = 0;
   
   // Đếm pending orders tại level này
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber && 
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(orderPrice - priceLevel) < tolerance)
            {
               ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               if(ot == ORDER_TYPE_BUY_STOP)
                  buyCount++;
               else if(ot == ORDER_TYPE_SELL_STOP)
                  sellCount++;
            }
         }
      }
   }
   
   // Đếm positions tại level này
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(posPrice - priceLevel) < tolerance)
            {
               ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               if(pt == POSITION_TYPE_BUY)
                  buyCount++;
               else if(pt == POSITION_TYPE_SELL)
                  sellCount++;
            }
         }
      }
   }
   
   // Mỗi level tối đa 1 Stop A (nếu cài) và 1 Stop B (nếu cài) → max 2 Buy, 2 Sell
   if(isBuyOrder && buyCount >= 2)
      return false;
   if(!isBuyOrder && sellCount >= 2)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Chuẩn hóa lot theo min/step/max của symbol                       |
//+------------------------------------------------------------------+
int GetVolumeDigitsFromStep(double step)
{
   if(step <= 0)
      return 2;
   for(int digits = 0; digits <= 8; digits++)
   {
      if(MathAbs(step - NormalizeDouble(step, digits)) < 1e-12)
         return digits;
   }
   return 8;
}

double NormalizeVolumeBySymbol(double volume)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(step <= 0)
      step = 0.01;
   if(minVol <= 0)
      minVol = step;
   if(maxVol <= 0)
      maxVol = volume;
   
   volume = MathMax(minVol, MathMin(maxVol, volume));
   
   // Làm tròn xuống theo step để tránh volume không hợp lệ
   double k = MathFloor(volume / step + 1e-9);
   double normalized = k * step;
   
   int digits = GetVolumeDigitsFromStep(step);
   normalized = NormalizeDouble(normalized, digits);
   if(normalized < minVol)
      normalized = NormalizeDouble(minVol, digits);
   
   return normalized;
}

//+------------------------------------------------------------------+
//| Đặt lệnh chờ với TP theo input (isStopA = Stop A, false = Stop B) |
//+------------------------------------------------------------------+
void PlacePendingOrder(ENUM_ORDER_TYPE orderType, double priceLevel, int levelNumber, bool isStopA)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lotSize = 0;
   double tp = 0;
   bool enableMartingale = false;
   ENUM_MARTINGALE_MODE martingaleMode = MARTINGALE_MODE_MULTIPLIER;
   double martingaleMultiplier = 1.0;
   double martingaleStep = 0.01;
   int maxLevels = 0;
   ENUM_TP_MODE tpMode = TP_MODE_FIXED_PIPS;
   double tpPips = 0;
   double maxLotCap = 0;
   string orderComment = "";
   
   if(isStopA)
   {
      lotSize = LotSizeStop;
      enableMartingale = EnableMartingaleStop;
      martingaleMode = MartingaleModeStop;
      martingaleMultiplier = MartingaleMultiplierStop;
      martingaleStep = MartingaleStepStop;
      maxLevels = MaxGridLevelsStop;
      tpMode = TakeProfitMode;
      tpPips = TakeProfitPipsStop;
      maxLotCap = MaxLotCap;
      orderComment = CommentOrder + " A";
   }
   else
   {
      lotSize = LotSizeStopB;
      maxLevels = MaxGridLevelsStopB;
      tpMode = TakeProfitModeB;
      tpPips = TakeProfitPipsStopB;
      maxLotCap = 0;
      orderComment = CommentOrder + " B";
   }
   
   if(orderType == ORDER_TYPE_BUY_STOP)
   {
      if(tpMode == TP_MODE_GRID_LEVEL)
      {
         if(levelNumber < maxLevels)
         {
            tp = GetLevelPrice(levelNumber + 1, ORDER_TYPE_BUY_STOP);
            if(tp > 0) tp = NormalizeDouble(tp, dgt);
         }
      }
      else if(tpPips > 0)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
   }
   else if(orderType == ORDER_TYPE_SELL_STOP)
   {
      if(tpMode == TP_MODE_GRID_LEVEL)
      {
         if(levelNumber < maxLevels)
         {
            tp = GetLevelPrice(levelNumber + 1, ORDER_TYPE_SELL_STOP);
            if(tp > 0) tp = NormalizeDouble(tp, dgt);
         }
      }
      else if(tpPips > 0)
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   
   int gridLevel = levelNumber;
   
   if(isStopA)
   {
      double savedLotSize = GetSavedLotSize(orderType, levelNumber);
      if(savedLotSize > 0)
      {
         lotSize = savedLotSize;
         Print("  → Sử dụng lot size đã lưu: ", lotSize, " cho mức ", levelNumber, " (A)");
      }
      else if(enableMartingale && gridLevel > 1)
      {
         int steps = gridLevel - 1;
         if(martingaleMode == MARTINGALE_MODE_ARITHMETIC && martingaleStep > 0)
            lotSize = lotSize + steps * martingaleStep;
         else if(martingaleMultiplier > 0)
            lotSize = lotSize * MathPow(martingaleMultiplier, steps);
      }
   }
   
   if(maxLotCap > 0 && lotSize > maxLotCap)
   {
      lotSize = maxLotCap;
      Print("  → Lot được giới hạn tại ", lotSize, " (tối đa ", maxLotCap, " lot)");
   }
   
   double rawLot = lotSize;
   lotSize = NormalizeVolumeBySymbol(lotSize);
   if(MathAbs(lotSize - rawLot) > 1e-10)
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      Print("  ⚠ Lot được làm tròn theo bước lot của symbol (step=", step, "): ", rawLot, " → ", lotSize);
   }
   
   bool result = false;
   if(orderType == ORDER_TYPE_BUY_STOP)
      result = trade.BuyStop(lotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, orderComment);
   else if(orderType == ORDER_TYPE_SELL_STOP)
      result = trade.SellStop(lotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, orderComment);
   
   if(result)
   {
      string ch = isStopA ? "A" : "B";
      string martingaleInfo = "";
      if(isStopA && enableMartingale && gridLevel > 1)
      {
         int steps = gridLevel - 1;
         martingaleInfo = " | Bậc " + IntegerToString(gridLevel);
         if(martingaleMode == MARTINGALE_MODE_ARITHMETIC)
            martingaleInfo += " (+" + DoubleToString(martingaleStep, 2) + ")";
         else
            martingaleInfo += " (x" + DoubleToString((steps > 0) ? MathPow(martingaleMultiplier, steps) : 1.0, 2) + ")";
      }
      Print("✓ Đã đặt lệnh Stop ", ch, ": ", EnumToString(orderType), " tại ", price, " | Lot: ", lotSize, " | TP: ", tp, martingaleInfo);
   }
   else
      Print("✗ Lỗi đặt lệnh Stop ", (isStopA ? "A" : "B"), " | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Lưu lot size cho mức lưới khi đạt TP                            |
//+------------------------------------------------------------------+
void SaveLotSizeForLevel(ENUM_ORDER_TYPE orderType, int levelNumber, double lotSize)
{
   if(levelNumber < 1 || levelNumber > MAX_GRID_LEVELS)
      return;
   
   int index = levelNumber - 1; // Mảng bắt đầu từ 0
   
   if(orderType == ORDER_TYPE_BUY_STOP)
      gridLotSizes.lotSizeBuyStop[index] = lotSize;
   else if(orderType == ORDER_TYPE_SELL_STOP)
      gridLotSizes.lotSizeSellStop[index] = lotSize;
}

//+------------------------------------------------------------------+
//| Lấy lot size đã lưu cho mức lưới                                |
//+------------------------------------------------------------------+
double GetSavedLotSize(ENUM_ORDER_TYPE orderType, int levelNumber)
{
   if(levelNumber < 1 || levelNumber > MAX_GRID_LEVELS)
      return 0;
   
   int index = levelNumber - 1;
   
   if(orderType == ORDER_TYPE_BUY_STOP)
      return gridLotSizes.lotSizeBuyStop[index];
   else if(orderType == ORDER_TYPE_SELL_STOP)
      return gridLotSizes.lotSizeSellStop[index];
   return 0;
}

//+------------------------------------------------------------------+
//| Lấy số mức lưới từ giá                                          |
//+------------------------------------------------------------------+
int GetGridLevelNumber(double price)
{
   double tolerance = GridDistancePips * pnt * 5.0;
   
   for(int i = 0; i < ArraySize(gridLevels); i++)
   {
      if(MathAbs(gridLevels[i] - price) < tolerance)
      {
         return gridLevelIndex[i];
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Lấy giá của mức lưới theo số mức và loại lệnh                  |
//+------------------------------------------------------------------+
double GetLevelPrice(int levelNumber, ENUM_ORDER_TYPE orderType)
{
   for(int i = 0; i < ArraySize(gridLevels); i++)
   {
      if(gridLevelIndex[i] == levelNumber)
      {
         double level = gridLevels[i];
         
         // Buy Stop trên gốc; Sell Stop dưới gốc
         if(orderType == ORDER_TYPE_SELL_STOP && level < basePrice)
            return level;
         if(orderType == ORDER_TYPE_BUY_STOP && level > basePrice)
            return level;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Kiểm tra điều kiện kích hoạt Trading Stop, Step Tổng           |
//+------------------------------------------------------------------+
void CheckTradingStopStepTotal()
{
   // Kiểm tra theo chế độ đã chọn
   if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
   {
      // Chế độ: Theo lệnh mở
      if(TradingStopStepTotalProfit <= 0)
         return;
      
      int buyCnt = 0, sellCnt = 0;
      double buyProfit = 0, sellProfit = 0, currentProfit = 0;
      GetPositionStats(buyCnt, sellCnt, buyProfit, sellProfit, currentProfit);
      if(currentProfit >= TradingStopStepTotalProfit)
      {
         // Chọn hướng theo giá so với đường gốc: giá trên đường gốc → Buy, giá dưới đường gốc → Sell
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool chosenBuy = (currentPrice >= basePrice);
         
         Print("========================================");
         Print("=== KÍCH HOẠT TRADING STOP, STEP TỔNG ===");
         Print("Chế độ: Theo lệnh mở");
         Print("Tổng lãi lệnh đang mở: ", currentProfit, " USD");
         Print("Mức kích hoạt: ", TradingStopStepTotalProfit, " USD");
         Print("Giá hiện tại: ", currentPrice, " | Đường gốc: ", basePrice);
         Print("Hướng: ", chosenBuy ? "BUY" : "SELL", " (giá ", chosenBuy ? "trên" : "dưới", " đường gốc)");
         Print("========================================");
         
         ActivateTradingStop(chosenBuy);
      }
   }
   else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
   {
      // Chế độ: Theo phiên
      if(TradingStopStepSessionProfit <= 0)
         return;
      
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double currentProfit = currentEquity - initialEquity;  // Lãi phiên = Vốn hiện tại - Vốn ban đầu
      
      if(currentProfit >= TradingStopStepSessionProfit)
      {
         // Chọn hướng theo giá so với đường gốc: giá trên đường gốc → Buy, giá dưới đường gốc → Sell
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool chosenBuy = (currentPrice >= basePrice);
         
         Print("========================================");
         Print("=== KÍCH HOẠT TRADING STOP, STEP TỔNG ===");
         Print("Chế độ: Theo phiên");
         Print("Tổng lãi phiên: ", currentProfit, " USD");
         Print("Mức kích hoạt: ", TradingStopStepSessionProfit, " USD");
         Print("Giá hiện tại: ", currentPrice, " | Đường gốc: ", basePrice);
         Print("Hướng: ", chosenBuy ? "BUY" : "SELL", " (giá ", chosenBuy ? "trên" : "dưới", " đường gốc)");
         Print("========================================");
         
         ActivateTradingStop(chosenBuy);
      }
   }
   else if(TradingStopStepMode == TRADING_STOP_MODE_BOTH)
   {
      // Chế độ: Tổ hợp cả 2 - ưu tiên cái đạt trước
      if(TradingStopStepTotalProfit <= 0 || TradingStopStepSessionProfit <= 0)
         return;
      
      int buyCnt = 0, sellCnt = 0;
      double buyProfit = 0, sellProfit = 0, openProfit = 0;
      GetPositionStats(buyCnt, sellCnt, buyProfit, sellProfit, openProfit);
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double sessionProfitVal = currentEquity - initialEquity;
      
      // Kiểm tra xem cái nào đạt trước
      bool openReached = (openProfit >= TradingStopStepTotalProfit);
      bool sessionReached = (sessionProfitVal >= TradingStopStepSessionProfit);
      
      if(openReached || sessionReached)
      {
         // Chọn hướng theo giá so với đường gốc: giá trên đường gốc → Buy, giá dưới đường gốc → Sell
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool chosenBuy = (currentPrice >= basePrice);
         
         Print("========================================");
         Print("=== KÍCH HOẠT TRADING STOP, STEP TỔNG ===");
         Print("Chế độ: Tổ hợp cả 2 (ưu tiên cái đạt trước)");
         Print("Tổng lãi lệnh đang mở: ", openProfit, " USD (ngưỡng: ", TradingStopStepTotalProfit, " USD) - ", (openReached ? "ĐẠT" : "Chưa đạt"));
         Print("Tổng lãi phiên: ", sessionProfitVal, " USD (ngưỡng: ", TradingStopStepSessionProfit, " USD) - ", (sessionReached ? "ĐẠT" : "Chưa đạt"));
         if(openReached && sessionReached)
            Print("Cả 2 điều kiện đều đạt - Kích hoạt");
         else if(openReached)
            Print("Điều kiện lệnh mở đạt trước - Kích hoạt");
         else
            Print("Điều kiện phiên đạt trước - Kích hoạt");
         Print("Giá hiện tại: ", currentPrice, " | Đường gốc: ", basePrice);
         Print("Hướng: ", chosenBuy ? "BUY" : "SELL", " (giá ", chosenBuy ? "trên" : "dưới", " đường gốc)");
         Print("========================================");
         
         ActivateTradingStop(chosenBuy);
      }
   }
}

//+------------------------------------------------------------------+
//| Kích hoạt Trading Stop - Xóa lệnh chờ gần giá → xóa TP → xóa lệnh chờ còn lại |
//| isBuyDirection: true = Buy, false = Sell                        |
//+------------------------------------------------------------------+
void ActivateTradingStop(bool isBuyDirection = true)
{
   isTradingStopActive = true;
   isTradingStopBuyDirection = isBuyDirection;
   firstStepDone = false;
   initialPriceForStop = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   lastPriceForStep = initialPriceForStop;
   
   // Thứ tự: 1) Xóa lệnh chờ gần giá hiện tại → 2) Xóa TP → 3) Xóa các lệnh chờ còn lại
   double currentPriceForActivate = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("=== BƯỚC 1: XÓA LỆNH CHỜ GẦN GIÁ HIỆN TẠI ===");
   
   // Thu thập lệnh chờ: ticket và khoảng cách tới giá hiện tại
   ulong orderTickets[];
   double orderDistances[];
   ArrayResize(orderTickets, 0);
   ArrayResize(orderDistances, 0);
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
         double dist = MathAbs(orderPrice - currentPriceForActivate);
         int n = ArraySize(orderTickets);
         ArrayResize(orderTickets, n + 1);
         ArrayResize(orderDistances, n + 1);
         orderTickets[n] = ticket;
         orderDistances[n] = dist;
      }
   }
   
   // Sắp xếp theo khoảng cách tăng dần (gần giá nhất trước)
   for(int i = 0; i < ArraySize(orderTickets) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(orderTickets); j++)
      {
         if(orderDistances[j] < orderDistances[i])
         {
            ulong tmpTicket = orderTickets[i];
            double tmpDist = orderDistances[i];
            orderTickets[i] = orderTickets[j];
            orderDistances[i] = orderDistances[j];
            orderTickets[j] = tmpTicket;
            orderDistances[j] = tmpDist;
         }
      }
   }
   
   // 1. Chỉ xóa lệnh chờ gần giá hiện tại nhất (lệnh có khoảng cách nhỏ nhất)
   double minDist = (ArraySize(orderDistances) > 0) ? orderDistances[0] : -1;
   int closeCount = 0;
   for(int i = 0; i < ArraySize(orderTickets) && orderDistances[i] <= minDist; i++)
   {
      if(!trade.OrderDelete(orderTickets[i]))
         Print("⚠ Lỗi xóa lệnh chờ gần giá ", orderTickets[i], ": ", GetLastError());
      else
      {
         Print("  ✓ Đã xóa lệnh chờ gần giá Ticket ", orderTickets[i], " (", orderDistances[i] / pnt / 10.0, " pips)");
         closeCount++;
      }
   }
   
   Print("=== BƯỚC 2: XÓA TP CÁC LỆNH ĐANG MỞ ===");
   // 2. Xóa TP của tất cả lệnh đang mở
   int tpCount = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         if(currentTP > 0)
         {
            double currentSL = PositionGetDouble(POSITION_SL);
            if(!trade.PositionModify(ticket, currentSL, 0))
               Print("⚠ Lỗi xóa TP cho position ", ticket, ": ", GetLastError());
            else
            {
               Print("  ✓ Đã xóa TP cho lệnh Ticket ", ticket);
               tpCount++;
            }
         }
      }
   }
   
   Print("=== BƯỚC 3: XÓA CÁC LỆNH CHỜ CÒN LẠI ===");
   // 3. Xóa các lệnh chờ còn lại (xa giá hơn)
   int remainingCount = 0;
   for(int i = closeCount; i < ArraySize(orderTickets); i++)
   {
      if(!trade.OrderDelete(orderTickets[i]))
         Print("⚠ Lỗi xóa lệnh chờ còn lại ", orderTickets[i], ": ", GetLastError());
      else
      {
         Print("  ✓ Đã xóa lệnh chờ còn lại Ticket ", orderTickets[i], " (", orderDistances[i] / pnt / 10.0, " pips)");
         remainingCount++;
      }
   }
   Print("✓ Hoàn tất: Xóa ", closeCount, " lệnh chờ gần giá → Xóa TP ", tpCount, " lệnh → Xóa ", remainingCount, " lệnh chờ còn lại");
   
   int _bc = 0, _sc = 0;
   double totalBuyProfit = 0, totalSellProfit = 0, _tot = 0;
   GetPositionStats(_bc, _sc, totalBuyProfit, totalSellProfit, _tot);
   Print("Tổng lệnh BUY (cả dương và âm): ", totalBuyProfit, " USD | Tổng lệnh SELL (cả dương và âm): ", totalSellProfit, " USD");
   Print("Hướng được chọn: ", isBuyDirection ? "BUY" : "SELL", " (giá ", isBuyDirection ? "trên" : "dưới", " đường gốc)");
   
   // 4. Tìm lệnh dương gần giá nhất TRONG HƯỚNG ĐƯỢC CHỌN và tính điểm A
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double nearestProfitPrice = 0.0;
   double minDistance = DBL_MAX;
   bool foundProfitPosition = false;
   Print("=== Tìm lệnh dương gần giá hiện tại nhất trong hướng ", (isBuyDirection ? "BUY" : "SELL"), " ===");
   Print("Giá hiện tại khi đạt ngưỡng: ", currentPrice);
   
   Print("--- Bước 3: Tìm lệnh DƯƠNG gần giá hiện tại nhất TRONG HƯỚNG ", (isBuyDirection ? "BUY" : "SELL"), " ---");
   Print("Lưu ý: Chỉ tìm lệnh DƯƠNG (đang lãi) trong hướng được chọn, bỏ qua lệnh âm và lệnh hướng ngược lại");
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            bool isBuy = (posType == POSITION_TYPE_BUY);
            
            // Tìm lệnh dương gần giá nhất TRONG HƯỚNG ĐƯỢC CHỌN
            // Điều kiện: (hướng được chọn là Buy VÀ lệnh là Buy VÀ lệnh dương) HOẶC (hướng được chọn là Sell VÀ lệnh là Sell VÀ lệnh dương)
            if((isBuyDirection && isBuy && positionProfit > 0) || (!isBuyDirection && !isBuy && positionProfit > 0))
            {
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double distance = MathAbs(openPrice - currentPrice);
               
               Print("  ✓ Lệnh ", (isBuy ? "BUY" : "SELL"), " DƯƠNG: Ticket ", ticket, " | Giá mở: ", openPrice, " | Lãi: ", positionProfit, " USD | Khoảng cách từ giá hiện tại: ", distance / pnt / 10.0, " pips");
               
               // Tìm lệnh dương gần giá nhất (khoảng cách nhỏ nhất)
               if(distance < minDistance)
               {
                  minDistance = distance;
                  nearestProfitPrice = openPrice;
                  foundProfitPosition = true;
                  Print("    → ĐƯỢC CHỌN: Lệnh dương gần giá hiện tại nhất trong hướng ", (isBuyDirection ? "BUY" : "SELL"), " (khoảng cách: ", distance / pnt / 10.0, " pips)");
               }
            }
         }
      }
   }
   
   Print("========================================");
   
   if(!foundProfitPosition)
   {
      Print("⚠ Không tìm thấy lệnh ", (isBuyDirection ? "Buy" : "Sell"), " dương nào để gồng lãi");
      isTradingStopActive = false;
      return;
   }
   
   // 4. Tính điểm A: từ lệnh dương gần giá nhất TRONG HƯỚNG ĐƯỢC CHỌN
   Print("--- Bước 3: Tính điểm A từ lệnh dương gần giá nhất trong hướng ", (isBuyDirection ? "BUY" : "SELL"), " ---");
   double pointADistance = TradingStopStepPointA * pnt * 10.0;
   
   if(isBuyDirection)
   {
      // Buy: điểm A = giá lệnh Buy dương gần nhất + X pips (phía trên)
      pointA = NormalizeDouble(nearestProfitPrice + pointADistance, dgt);
      Print("  - Công thức: Điểm A = Giá lệnh Buy dương gần nhất + ", TradingStopStepPointA, " pips");
      Print("  - Điểm A = ", nearestProfitPrice, " + ", TradingStopStepPointA, " pips = ", pointA);
   }
   else
   {
      // Sell: điểm A = giá lệnh Sell dương gần nhất - X pips (phía dưới)
      pointA = NormalizeDouble(nearestProfitPrice - pointADistance, dgt);
      Print("  - Công thức: Điểm A = Giá lệnh Sell dương gần nhất - ", TradingStopStepPointA, " pips");
      Print("  - Điểm A = ", nearestProfitPrice, " - ", TradingStopStepPointA, " pips = ", pointA);
   }
   
   Print("========================================");
   Print("✓ ĐÃ TÍNH ĐIỂM A THÀNH CÔNG");
   Print("  - Hướng được chọn: ", (isBuyDirection ? "BUY" : "SELL"));
   Print("  - Giá hiện tại khi đạt ngưỡng: ", currentPrice);
   Print("  - Lệnh dương gần giá nhất: ", (isBuyDirection ? "BUY" : "SELL"), " tại giá ", nearestProfitPrice);
   Print("  - Khoảng cách từ giá hiện tại đến lệnh dương: ", minDistance / pnt / 10.0, " pips");
   Print("  - Điểm A cách lệnh dương: ", TradingStopStepPointA, " pips");
   Print("  - Điểm A = ", pointA);
   Print("  - Đã xóa TP của TẤT CẢ lệnh (CẢ BUY VÀ SELL, cả dương và âm)");
   Print("  - Khi giá đi đến điểm A + ", TradingStopStepSize, " pips sẽ đặt SL tại điểm A cho TẤT CẢ lệnh ", (isBuyDirection ? "BUY" : "SELL"));
   Print("  - SAU KHI đặt SL xong sẽ đóng TẤT CẢ lệnh ", (isBuyDirection ? "SELL" : "BUY"), " (lệnh ngược hướng)");
   Print("  - KHÔNG đóng lệnh ngay khi kích hoạt - chỉ xóa lệnh chờ và xóa TP");
}

//+------------------------------------------------------------------+
//| Quản lý Trading Stop - Đóng lệnh âm, di chuyển SL theo step    |
//+------------------------------------------------------------------+
void ManageTradingStop()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stepDistance = TradingStopStepSize * pnt * 10.0;
   
   // Kiểm tra nếu chưa hoàn thành step đầu tiên và tổng lãi giảm xuống
   if(!firstStepDone)
   {
      int _b = 0, _s = 0;
      double _bp = 0, _sp = 0, openProfitVal = 0;
      GetPositionStats(_b, _s, _bp, _sp, openProfitVal);
      
      double currentProfit = 0.0;
      double threshold = 0.0;
      string profitType = "";
      bool shouldCheckReturn = false;
      
      // Tính tổng lãi theo chế độ đã chọn
      if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
      {
         // Chế độ: Theo lệnh mở
         currentProfit = openProfitVal;
         threshold = TradingStopStepTotalProfit;
         profitType = "lệnh đang mở";
         shouldCheckReturn = true;
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
      {
         // Chế độ: Theo phiên
         double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         currentProfit = currentEquity - initialEquity;  // Lãi phiên = Vốn hiện tại - Vốn ban đầu
         threshold = TradingStopStepSessionProfit;
         profitType = "phiên";
         shouldCheckReturn = true;
      }
      else if(TradingStopStepMode == TRADING_STOP_MODE_BOTH)
      {
         // Chế độ: Tổ hợp cả 2 - kiểm tra cả 2 điều kiện
         double openProfit = openProfitVal;
         double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         double sessionProfitVal = currentEquity - initialEquity;
         
         // Kiểm tra xem cả 2 điều kiện có còn đạt không
         bool openStillReached = (openProfit >= TradingStopStepTotalProfit);
         bool sessionStillReached = (sessionProfitVal >= TradingStopStepSessionProfit);
         
         // Nếu cả 2 điều kiện đều không đạt nữa, kiểm tra ngưỡng quay lại
         if(!openStillReached && !sessionStillReached)
         {
            // Kiểm tra xem có điều kiện nào >= ngưỡng quay lại tương ứng không
            if(openProfit >= TradingStopStepReturnProfitOpen || sessionProfitVal >= TradingStopStepReturnProfitSession)
            {
               // Vẫn ở chế độ Trading Stop, chỉ log
               static int logCount = 0;
               logCount++;
               if(logCount % 100 == 0)
               {
                  Print("Trading Stop đang chờ - Lệnh mở: ", openProfit, " USD, Phiên: ", sessionProfitVal, " USD");
               }
            }
            else
            {
               // Cả 2 điều kiện đều < ngưỡng quay lại → Hủy Trading Stop
               Print("========================================");
               Print("=== HỦY TRADING STOP - TỔNG LÃI GIẢM ===");
               Print("Chế độ: Tổ hợp cả 2");
               Print("Tổng lãi lệnh mở: ", openProfit, " USD (ngưỡng: ", TradingStopStepTotalProfit, " USD)");
               Print("Tổng lãi phiên: ", sessionProfitVal, " USD (ngưỡng: ", TradingStopStepSessionProfit, " USD)");
               Print("Ngưỡng quay lại (lệnh mở): ", TradingStopStepReturnProfitOpen, " USD");
               Print("Ngưỡng quay lại (phiên): ", TradingStopStepReturnProfitSession, " USD");
               Print("CHƯA ĐẶT SL (chưa đến điểm A + step) → Khôi phục lại trạng thái ban đầu");
               Print("EA sẽ khôi phục lại bình thường: Khôi phục TP cho TẤT CẢ lệnh và tạo lại lệnh chờ");
               Print("========================================");
               
               // 1. Khôi phục TP cho TẤT CẢ lệnh đang mở theo input (có TP khi đã cài input)
               RestoreTPForAllPositions();
               
               // Hủy chế độ Trading Stop
               isTradingStopActive = false;
               pointA = 0.0;
               initialPointA = 0.0;
               lastPriceForStep = 0.0;
               initialPriceForStop = 0.0;
               firstStepDone = false;
               
               // 2. Khôi phục lệnh chờ đã xóa: tạo lại với TP theo input (có TP khi đã cài input)
               Print("=== KHÔI PHỤC LẠI LỆNH CHỜ ĐÃ XÓA (TP THEO INPUT) ===");
               ManageGridOrders();
               Print("✓ Đã khôi phục: lệnh đang mở có TP theo input, lệnh chờ mới có TP theo input - EA tiếp tục chạy");
               
               return;
            }
         }
         // Nếu ít nhất 1 điều kiện vẫn đạt, tiếp tục chế độ Trading Stop
         shouldCheckReturn = false;
      }
      
      // Kiểm tra ngưỡng quay lại cho chế độ OPEN hoặc SESSION
      if(shouldCheckReturn && currentProfit < threshold)
      {
         // Xác định ngưỡng quay lại tương ứng
         double returnThreshold = 0.0;
         if(TradingStopStepMode == TRADING_STOP_MODE_OPEN)
         {
            returnThreshold = TradingStopStepReturnProfitOpen;
         }
         else if(TradingStopStepMode == TRADING_STOP_MODE_SESSION)
         {
            returnThreshold = TradingStopStepReturnProfitSession;
         }
         
         // Nếu >= ngưỡng quay lại, tiếp tục chế độ Trading Stop
         if(currentProfit >= returnThreshold)
         {
            // Vẫn ở chế độ Trading Stop, chỉ log
            static int logCount = 0;
            logCount++;
            if(logCount % 100 == 0)
            {
               Print("Trading Stop đang chờ - Tổng lãi ", profitType, ": ", currentProfit, " USD (ngưỡng: ", threshold, " USD)");
            }
         }
         else
         {
            // Tổng lãi < ngưỡng quay lại → Hủy Trading Stop, khôi phục bình thường
            Print("========================================");
            Print("=== HỦY TRADING STOP - TỔNG LÃI GIẢM ===");
            string modeText = (TradingStopStepMode == TRADING_STOP_MODE_OPEN) ? "Theo lệnh mở" : "Theo phiên";
            Print("Chế độ: ", modeText);
            Print("Tổng lãi ", profitType, " hiện tại: ", currentProfit, " USD");
            Print("Ngưỡng quay lại: ", returnThreshold, " USD");
            Print("CHƯA ĐẶT SL (chưa đến điểm A + step) → Khôi phục lại trạng thái ban đầu");
            Print("EA sẽ khôi phục lại bình thường: Khôi phục TP cho TẤT CẢ lệnh và tạo lại lệnh chờ");
            Print("========================================");
            
            // 1. Khôi phục TP cho TẤT CẢ lệnh đang mở theo input (có TP khi đã cài input)
            RestoreTPForAllPositions();
            
            // Hủy chế độ Trading Stop
            isTradingStopActive = false;
            pointA = 0.0;
            initialPointA = 0.0;
            lastPriceForStep = 0.0;
            initialPriceForStop = 0.0;
            firstStepDone = false;
            
            // 2. Khôi phục lệnh chờ đã xóa: tạo lại với TP theo input (có TP khi đã cài input)
            Print("=== KHÔI PHỤC LẠI LỆNH CHỜ ĐÃ XÓA (TP THEO INPUT) ===");
            ManageGridOrders();
            Print("✓ Đã khôi phục: lệnh đang mở có TP theo input, lệnh chờ mới có TP theo input - EA tiếp tục chạy");
            
            return;
         }
      }
   }
   
   // Lưu điểm A ban đầu khi hoàn thành step đầu tiên
   if(!firstStepDone)
   {
      // initialPointA sẽ được set sau khi đặt SL lần đầu
   }
   
   // 1. Step đầu tiên: Khi giá đi đến điểm A + 1 step
   //    → Đặt SL tại điểm A cho TẤT CẢ lệnh cùng hướng, đóng hết lệnh ngược còn lại, bắt đầu gồng lãi
   if(!firstStepDone)
   {
      double targetPrice = 0.0;
      bool shouldSetSL = false;
      
      if(!isTradingStopBuyDirection) // Sell
      {
         // Với Sell: giá đi xuống đến điểm A - 1 step
         // Điểm A ở phía dưới, nên giá cần <= điểm A - 1 step
         targetPrice = NormalizeDouble(pointA - stepDistance, dgt);
         if(currentPrice <= targetPrice)
         {
            shouldSetSL = true;
            Print("=== ĐIỀU KIỆN ĐẠT: Giá đi đến A - 1 step ===");
            Print("  - Điểm A: ", pointA);
            Print("  - Giá hiện tại: ", currentPrice, " <= ", targetPrice, " (A - 1 step)");
            Print("  - Sẽ đặt SL tại điểm A cho TẤT CẢ lệnh ", (isTradingStopBuyDirection ? "BUY" : "SELL"), ", sau đó đóng lệnh ngược hướng");
         }
      }
      else
      {
         // Với Buy: giá đi lên đến điểm A + 1 step
         // Điểm A ở phía trên, nên giá cần >= điểm A + 1 step
         targetPrice = NormalizeDouble(pointA + stepDistance, dgt);
         if(currentPrice >= targetPrice)
         {
            shouldSetSL = true;
            Print("=== ĐIỀU KIỆN ĐẠT: Giá đi đến A + 1 step ===");
            Print("  - Điểm A: ", pointA);
            Print("  - Giá hiện tại: ", currentPrice, " >= ", targetPrice, " (A + 1 step)");
            Print("  - Sẽ đặt SL tại điểm A cho TẤT CẢ lệnh ", (isTradingStopBuyDirection ? "BUY" : "SELL"), ", sau đó đóng lệnh ngược hướng");
         }
      }
      
      if(shouldSetSL)
      {
         Print("=== BƯỚC 1: ĐẶT SL TẠI ĐIỂM A ===");
         // Đặt SL tại điểm A cho TẤT CẢ lệnh cùng hướng
         SetSLToPointAForAllPositions(isTradingStopBuyDirection);
         
         Print("=== BƯỚC 2: ĐÓNG TẤT CẢ LỆNH NGƯỢC HƯỚNG ===");
         // Đóng hết lệnh ngược còn lại
         CloseAllOppositePositions(isTradingStopBuyDirection);
         
         Print("=== BƯỚC 3: BẮT ĐẦU GỒNG LÃI ===");
         firstStepDone = true;
         initialPointA = pointA; // Lưu điểm A ban đầu để tính trailing
         lastPriceForStep = targetPrice; // Lưu giá tại step 1
         Print("✓ Đã đặt SL tại điểm A (", pointA, ") và đóng lệnh ngược hướng - Bắt đầu gồng lãi");
         Print("  - Điểm A ban đầu: ", initialPointA);
         Print("  - Khi giá đi đến A + 2step, SL sẽ được dịch lên A + 1step");
      }
   }
   else
   {
      // 2. Gồng lãi: Khi giá đi tiếp step pips nữa (theo hướng có lợi) thì dịch SL theo 1 step
      //    Buy: giá đi lên step pips → dịch SL lên step; Sell: giá đi xuống step pips → dịch SL xuống step
      double priceChange = 0.0;
      double newSL = pointA;
      bool shouldUpdateSL = false;
      
      if(!isTradingStopBuyDirection) // Sell
      {
         // Với Sell: CHỈ dịch SL xuống khi giá đi xuống thêm 1 step
         // KHÔNG dịch SL khi giá đi lên
         priceChange = lastPriceForStep - currentPrice; // Giá đi xuống → priceChange > 0
         
         if(priceChange >= stepDistance)
         {
            // Giá đi xuống thêm 1 step → dịch SL xuống 1 step
            newSL = NormalizeDouble(pointA - stepDistance, dgt);
            shouldUpdateSL = true;
            
            Print("=== STEP TIẾP: Giá đi xuống thêm ", TradingStopStepSize, " pips - Dịch SL xuống ===");
            Print("  - Giá cũ: ", lastPriceForStep);
            Print("  - Giá mới: ", currentPrice);
            Print("  - Khoảng cách: ", priceChange / pnt / 10.0, " pips");
            Print("  - SL cũ: ", pointA);
            Print("  - SL mới: ", newSL, " (dịch xuống ", TradingStopStepSize, " pips)");
         }
         else if(currentPrice > lastPriceForStep)
         {
            // Giá đi lên → KHÔNG dịch SL, chỉ log
            static int logCountSell = 0;
            logCountSell++;
            if(logCountSell % 100 == 0)
            {
               Print("  - Giá đi lên (", currentPrice, " > ", lastPriceForStep, ") - KHÔNG dịch SL (chờ giá đi xuống)");
            }
         }
      }
      else // Buy
      {
         // Với Buy: CHỈ dịch SL lên khi giá đi lên thêm 1 step
         // KHÔNG dịch SL khi giá đi xuống
         priceChange = currentPrice - lastPriceForStep; // Giá đi lên → priceChange > 0
         
         if(priceChange >= stepDistance)
         {
            // Giá đi lên thêm 1 step → dịch SL lên 1 step
            newSL = NormalizeDouble(pointA + stepDistance, dgt);
            shouldUpdateSL = true;
            
            Print("=== STEP TIẾP: Giá đi lên thêm ", TradingStopStepSize, " pips - Dịch SL lên ===");
            Print("  - Giá cũ: ", lastPriceForStep);
            Print("  - Giá mới: ", currentPrice);
            Print("  - Khoảng cách: ", priceChange / pnt / 10.0, " pips");
            Print("  - SL cũ: ", pointA);
            Print("  - SL mới: ", newSL, " (dịch lên ", TradingStopStepSize, " pips)");
         }
         else if(currentPrice < lastPriceForStep)
         {
            // Giá đi xuống → KHÔNG dịch SL, chỉ log
            static int logCountBuy = 0;
            logCountBuy++;
            if(logCountBuy % 100 == 0)
            {
               Print("  - Giá đi xuống (", currentPrice, " < ", lastPriceForStep, ") - KHÔNG dịch SL (chờ giá đi lên)");
            }
         }
      }
      
      // Cập nhật SL nếu cần
      if(shouldUpdateSL)
      {
         // Cập nhật SL cho TẤT CẢ lệnh cùng hướng
         pointA = newSL;
         UpdateSLForAllPositions(newSL, isTradingStopBuyDirection);
         
         // Cập nhật lastPriceForStep để theo dõi step tiếp theo
         lastPriceForStep = currentPrice;
         
         Print("✓ Đã dịch SL ", (isTradingStopBuyDirection ? "lên" : "xuống"), " ", newSL, " cho TẤT CẢ lệnh ", (isTradingStopBuyDirection ? "BUY" : "SELL"));
      }
      
      // Kiểm tra xem giá có quay đầu chạm SL không
      bool priceHitSL = false;
      if(!isTradingStopBuyDirection) // Sell
      {
         // Với Sell: giá tăng lên >= điểm A (SL)
         if(currentPrice >= pointA)
         {
            priceHitSL = true;
         }
      }
      else
      {
         // Với Buy: giá giảm xuống <= điểm A (SL)
         if(currentPrice <= pointA)
         {
            priceHitSL = true;
         }
      }
      
      if(priceHitSL)
      {
         Print("========================================");
         Print("=== GIÁ QUAY ĐẦU CHẠM SL ===");
         Print("Giá hiện tại: ", currentPrice);
         Print("Điểm A (SL): ", pointA);
         
         ENUM_TP_ACTION actionToUse = ActionOnTradingStopStepComplete;
         string actionText = "";
         if(actionToUse == TP_ACTION_RESET_EA)
            actionText = "Reset EA";
         else if(actionToUse == TP_ACTION_STOP_EA)
            actionText = "Dừng EA";
         else
            actionText = "Khôi phục bình thường";
         
         Print("Hành động: ", actionText);
         Print("========================================");
         
         // Reset biến Trading Stop
         isTradingStopActive = false;
         pointA = 0.0;
         initialPointA = 0.0;
         lastPriceForStep = 0.0;
         initialPriceForStop = 0.0;
         firstStepDone = false;
         
         // Thực hiện hành động theo cài đặt
         if(actionToUse == TP_ACTION_RESET_EA)
         {
            ResetEA("Trading Stop, Step Tổng");
         }
         else
         {
            StopEA();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Đóng tất cả lệnh âm (đang lỗ)                                   |
//+------------------------------------------------------------------+
void CloseNegativePositions()
{
   int closedCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Chỉ đóng lệnh âm (đang lỗ)
            if(positionProfit < 0)
            {
               if(trade.PositionClose(ticket))
               {
                  closedCount++;
                  Print("✓ Đã đóng lệnh âm: Ticket ", ticket, " | Profit: ", positionProfit, " USD");
               }
            }
         }
      }
   }
   
   Print("Đã đóng ", closedCount, " lệnh âm");
}

//+------------------------------------------------------------------+
//| Đặt SL tại điểm A cho tất cả lệnh dương                         |
//+------------------------------------------------------------------+
void SetSLToPointAForProfitPositions()
{
   int modifiedCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Chỉ set SL cho lệnh dương
            if(positionProfit > 0)
            {
               if(trade.PositionModify(ticket, pointA, 0))
               {
                  modifiedCount++;
                  Print("✓ Đã set SL tại điểm A (", pointA, ") cho position ", ticket);
               }
               else
               {
                  Print("⚠ Lỗi set SL cho position ", ticket, ": ", GetLastError());
               }
            }
         }
      }
   }
   
   Print("Đã set SL tại điểm A cho ", modifiedCount, " lệnh dương");
}

//+------------------------------------------------------------------+
//| Đặt SL tại điểm A cho TẤT CẢ lệnh cùng hướng (BUY hoặc Sell)   |
//+------------------------------------------------------------------+
void SetSLToPointAForAllPositions(bool isBuyDirection)
{
   int modifiedCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool isBuy = (posType == POSITION_TYPE_BUY);
            
            // Chỉ set SL cho lệnh cùng hướng
            if(isBuy == isBuyDirection)
            {
               if(trade.PositionModify(ticket, pointA, 0))
               {
                  modifiedCount++;
                  double positionProfit = PositionGetDouble(POSITION_PROFIT);
                  Print("✓ Đã set SL tại điểm A (", pointA, ") cho ", (isBuy ? "BUY" : "SELL"), " position ", ticket, " (Profit: ", positionProfit, " USD)");
               }
               else
               {
                  Print("⚠ Lỗi set SL cho position ", ticket, ": ", GetLastError());
               }
            }
         }
      }
   }
   
   Print("Đã set SL tại điểm A cho ", modifiedCount, " lệnh ", (isBuyDirection ? "BUY" : "SELL"), " (tất cả, không chỉ lệnh dương)");
}

//+------------------------------------------------------------------+
//| Cập nhật SL cho tất cả lệnh dương theo điểm A mới               |
//+------------------------------------------------------------------+
void UpdateSLForProfitPositions(double newSL)
{
   int modifiedCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Chỉ update SL cho lệnh dương
            if(positionProfit > 0)
            {
               if(trade.PositionModify(ticket, newSL, 0))
               {
                  modifiedCount++;
               }
            }
         }
      }
   }
   
   if(modifiedCount > 0)
   {
      Print("✓ Đã cập nhật SL cho ", modifiedCount, " lệnh dương tại ", newSL);
   }
}

//+------------------------------------------------------------------+
//| Cập nhật SL cho TẤT CẢ lệnh cùng hướng (BUY hoặc Sell)         |
//+------------------------------------------------------------------+
void UpdateSLForAllPositions(double newSL, bool isBuyDirection)
{
   int modifiedCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool isBuy = (posType == POSITION_TYPE_BUY);
            
            // Chỉ update SL cho lệnh cùng hướng
            if(isBuy == isBuyDirection)
            {
               if(trade.PositionModify(ticket, newSL, 0))
               {
                  modifiedCount++;
               }
            }
         }
      }
   }
   
   if(modifiedCount > 0)
   {
      Print("✓ Đã cập nhật SL cho ", modifiedCount, " lệnh ", (isBuyDirection ? "BUY" : "SELL"), " tại ", newSL, " (tất cả, không chỉ lệnh dương)");
   }
}

//+------------------------------------------------------------------+
//| Trading Stop cho từng lệnh Stop B: khi giá cách entry X pips đặt SL dương, |
//| giá đi thêm step thì dịch SL theo step                            |
//+------------------------------------------------------------------+
void ManageTradingStopStopB()
{
   if(!EnableTradingStopStopB || !EnableStopOrdersB || TradingStopStopBDistancePips <= 0)
      return;
   if(eaStopped)
      return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distancePrice = TradingStopStopBDistancePips * pnt * 10.0;
   double stepPrice = (TradingStopStopBStepPips > 0) ? (TradingStopStopBStepPips * pnt * 10.0) : 0;
   string commentB = CommentOrder + " B";
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetString(POSITION_COMMENT) != commentB)
         continue;
      
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      
      double newSL = 0;
      if(isBuy)
      {
         if(bid < entry + distancePrice)
            continue;
         if(stepPrice <= 0)
            newSL = NormalizeDouble(entry, dgt);
         else
         {
            double profitPips = (bid - entry - distancePrice) / (pnt * 10.0);
            int steps = (int)MathFloor(profitPips / TradingStopStopBStepPips);
            newSL = NormalizeDouble(entry + steps * stepPrice, dgt);
         }
         if(newSL <= entry) newSL = NormalizeDouble(entry, dgt);
         if(currentSL > 0 && newSL <= currentSL)
            continue;
      }
      else
      {
         if(bid > entry - distancePrice)
            continue;
         if(stepPrice <= 0)
            newSL = NormalizeDouble(entry, dgt);
         else
         {
            double profitPips = (entry - bid - distancePrice) / (pnt * 10.0);
            int steps = (int)MathFloor(profitPips / TradingStopStopBStepPips);
            newSL = NormalizeDouble(entry - steps * stepPrice, dgt);
         }
         if(newSL >= entry) newSL = NormalizeDouble(entry, dgt);
         if(currentSL > 0 && newSL >= currentSL)
            continue;
      }
      
      if(trade.PositionModify(ticket, newSL, currentTP))
      {
         static int logCount = 0;
         if(logCount++ % 20 == 0)
            Print("✓ Trading Stop B: ", (isBuy ? "BUY" : "SELL"), " ticket ", ticket, " SL=", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Đóng hết lệnh ngược hướng còn lại (khi đặt SL)                 |
//+------------------------------------------------------------------+
void CloseAllOppositePositions(bool isBuyDirection)
{
   int closedCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            bool isBuy = (posType == POSITION_TYPE_BUY);
            
            // Chỉ đóng lệnh ngược hướng
            if(isBuy != isBuyDirection)
            {
               double positionProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               if(trade.PositionClose(ticket))
               {
                  closedCount++;
                  Print("✓ Đã đóng lệnh ngược ", (isBuy ? "BUY" : "SELL"), ": Ticket ", ticket, " (Profit: ", positionProfit, " USD)");
               }
            }
         }
      }
   }
   
   if(closedCount > 0)
   {
      Print("✓ Đã đóng ", closedCount, " lệnh ngược hướng còn lại");
   }
   else
   {
      Print("✓ Không còn lệnh ngược hướng nào để đóng");
   }
}

//+------------------------------------------------------------------+
//| Khôi phục TP cho tất cả lệnh dương (khi hủy Trading Stop)       |
//+------------------------------------------------------------------+
void RestoreTPForProfitPositions()
{
   int restoredCount = 0;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            // Chỉ khôi phục TP cho lệnh dương
            if(positionProfit > 0)
            {
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               double tp = 0;
               int levelNum = GetGridLevelNumber(openPrice);
               
               if(TakeProfitMode == TP_MODE_GRID_LEVEL && levelNum >= 1 && levelNum < MaxGridLevelsStop)
               {
                  ENUM_ORDER_TYPE ot = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
                  tp = GetLevelPrice(levelNum + 1, ot);
                  if(tp > 0) tp = NormalizeDouble(tp, dgt);
               }
               else if(TakeProfitPipsStop > 0)
               {
                  if(posType == POSITION_TYPE_BUY)
                     tp = NormalizeDouble(openPrice + TakeProfitPipsStop * pnt * 10.0, dgt);
                  else
                     tp = NormalizeDouble(openPrice - TakeProfitPipsStop * pnt * 10.0, dgt);
               }
               
               // Khôi phục TP (giữ nguyên SL hiện tại nếu có)
               double currentSL = PositionGetDouble(POSITION_SL);
               if(tp > 0)
               {
                  if(trade.PositionModify(ticket, currentSL, tp))
                  {
                     restoredCount++;
                     Print("✓ Đã khôi phục TP (", tp, ") cho position ", ticket);
                  }
                  else
                  {
                     Print("⚠ Lỗi khôi phục TP cho position ", ticket, ": ", GetLastError());
                  }
               }
            }
         }
      }
   }
   
   if(restoredCount > 0)
   {
      Print("Đã khôi phục TP cho ", restoredCount, " lệnh dương");
   }
}

//+------------------------------------------------------------------+
//| Khôi phục TP cho TẤT CẢ lệnh đang mở (cả dương và âm) theo input |
//| Bắt buộc: mọi lệnh đang mở phải có TP đúng như đã cài ở input (khi input > 0) |
//| Dùng khi hủy Trading Stop trước khi đặt SL - khôi phục trạng thái trước khi đạt ngưỡng |
//| SL luôn đặt = 0 để giống trạng thái ban đầu (EA không dùng SL trên position) |
//+------------------------------------------------------------------+
void RestoreTPForAllPositions()
{
   int restoredCount = 0;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double tp = 0;
            int levelNum = GetGridLevelNumber(openPrice);
            
            if(TakeProfitMode == TP_MODE_GRID_LEVEL && levelNum >= 1 && levelNum < MaxGridLevelsStop)
            {
               ENUM_ORDER_TYPE ot = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
               tp = GetLevelPrice(levelNum + 1, ot);
               if(tp > 0) tp = NormalizeDouble(tp, dgt);
            }
            else if(TakeProfitPipsStop > 0)
            {
               if(posType == POSITION_TYPE_BUY)
                  tp = NormalizeDouble(openPrice + TakeProfitPipsStop * pnt * 10.0, dgt);
               else
                  tp = NormalizeDouble(openPrice - TakeProfitPipsStop * pnt * 10.0, dgt);
            }
            
            // Khôi phục TP, SL = 0 (trạng thái như trước khi kích hoạt Trading Stop)
            if(tp > 0)
            {
               if(trade.PositionModify(ticket, 0, tp))
               {
                  restoredCount++;
                  double positionProfit = PositionGetDouble(POSITION_PROFIT);
                  Print("✓ Đã khôi phục TP (", tp, ") cho ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " position ", ticket, " (Profit: ", positionProfit, " USD)");
               }
               else
               {
                  Print("⚠ Lỗi khôi phục TP cho position ", ticket, ": ", GetLastError());
               }
            }
            else
            {
               // TP = 0 trong input: đảm bảo position không có TP (và SL = 0)
               double currentTP = PositionGetDouble(POSITION_TP);
               double currentSL = PositionGetDouble(POSITION_SL);
               if(currentTP > 0 || currentSL != 0)
               {
                  if(trade.PositionModify(ticket, 0, 0))
                     Print("✓ Đã xóa TP/SL cho position ", ticket, " (TP = 0 trong input)");
               }
            }
         }
      }
   }
   
   if(restoredCount > 0)
   {
      Print("Đã khôi phục TP cho ", restoredCount, " lệnh đang mở (cả dương và âm) theo input");
   }
   else
   {
      Print("Không có lệnh nào cần khôi phục TP (TP = 0 trong input hoặc không có lệnh)");
   }
}

//+------------------------------------------------------------------+
//| Lấy lot lớn nhất của lệnh đang mở                                |
//+------------------------------------------------------------------+
double GetMaxLot()
{
   double maxLot = 0.0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            if(lotSize > maxLot)
               maxLot = lotSize;
         }
      }
   }
   
   return maxLot;
}

//+------------------------------------------------------------------+
//| Lấy tổng lot của lệnh đang mở                                     |
//+------------------------------------------------------------------+
double GetTotalLot()
{
   double totalLot = 0.0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            totalLot += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   
   return totalLot;
}

//+------------------------------------------------------------------+
//| Cập nhật thông tin theo dõi (không có panel)                     |
//+------------------------------------------------------------------+
void UpdateTrackingInfo()
{
   // Theo dõi vốn thấp nhất (khi lỗ lớn nhất)
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(minEquity == 0.0 || currentEquity < minEquity)
   {
      minEquity = currentEquity;
   }
   
   // Tính số âm lớn nhất của lệnh đang mở (một lần duyệt)
   int _bc = 0, _sc = 0;
   double _bp = 0, _sp = 0, currentOpenProfit = 0;
   GetPositionStats(_bc, _sc, _bp, _sp, currentOpenProfit);
   if(currentOpenProfit < maxNegativeProfit)
   {
      maxNegativeProfit = currentOpenProfit;
      balanceAtMaxLoss = AccountInfoDouble(ACCOUNT_BALANCE);  // Lưu số dư tại thời điểm có số âm lớn nhất
   }
   
   // Số lot lớn nhất (cập nhật giá trị lớn nhất từng có, không reset khi EA reset)
   double maxLot = GetMaxLot();
   if(maxLot > maxLotEver)
      maxLotEver = maxLot;
   
   // Tổng lot lớn nhất (cập nhật giá trị lớn nhất từng có, không reset khi EA reset)
   double totalLot = GetTotalLot();
   if(totalLot > totalLotEver)
      totalLotEver = totalLot;
}

//+------------------------------------------------------------------+
//| Format số tiền với K và M                                          |
//+------------------------------------------------------------------+
string FormatMoney(double amount)
{
   string result = "";
   double absAmount = MathAbs(amount);
   
   if(absAmount >= 1000000.0)
   {
      // Triệu (M)
      double mValue = absAmount / 1000000.0;
      result = DoubleToString(mValue, 2) + "M";
   }
   else if(absAmount >= 1000.0)
   {
      // Nghìn (K)
      double kValue = absAmount / 1000.0;
      result = DoubleToString(kValue, 2) + "K";
   }
   else
   {
      // Dưới 1000
      result = DoubleToString(absAmount, 2);
   }
   
   // Thêm dấu âm nếu cần
   if(amount < 0)
      result = "-" + result;
   
   return result + "$";
}

//+------------------------------------------------------------------+
//| Gửi thông báo về điện thoại khi EA reset                          |
//+------------------------------------------------------------------+
void SendResetNotification(string resetReason, double accumulatedBefore, double profitThisTime, double accumulatedAfter, int resetNumber)
{
   // 1. Biểu đồ
   string symbolName = _Symbol;
   
   // 2. EA Reset về chức năng gì
   string functionName = resetReason;
   
   // 3. Số dư hiện tại
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   string balanceText = FormatMoney(currentBalance);
   
   // 4. Số tiền lỗ lớn nhất / vốn (%)
   double maxLoss = maxNegativeProfit;
   double maxLossPercent = (balanceAtMaxLoss > 0) ? (MathAbs(maxLoss) / balanceAtMaxLoss * 100.0) : 0.0;
   string maxLossText = FormatMoney(maxLoss) + " / " + FormatMoney(balanceAtMaxLoss) + " (" + DoubleToString(maxLossPercent, 2) + "%)";
   
   // 5. Số lot lớn nhất / tổng lot lớn nhất
   string lotText = DoubleToString(maxLotEver, 2) + " / " + DoubleToString(totalLotEver, 2);
   
   // 6. Tích lũy với số lần
   string accumulatedText = "Tích lũy lần " + IntegerToString(resetNumber) + ": " + FormatMoney(accumulatedBefore) + " + " + FormatMoney(profitThisTime) + " = " + FormatMoney(accumulatedAfter);
   
   // Tạo nội dung thông báo
   string message = "EA RESET\n";
   message += "Biểu đồ: " + symbolName + "\n";
   message += "Chức năng: " + functionName + "\n";
   message += "Số dư: " + balanceText + "\n";
   message += accumulatedText + "\n";
   message += "Lỗ lớn nhất: " + maxLossText + "\n";
   message += "Lot: " + lotText;
   
   // Gửi thông báo
   SendNotification(message);
   
   Print("========================================");
   Print("Đã gửi thông báo về điện thoại:");
   Print(message);
   Print("========================================");
}
