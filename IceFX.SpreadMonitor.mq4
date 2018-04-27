//+------------------------------------------------------------------+
//|                                              IceFX.SpreadMonitor |
//|                                    Copyright © 2017, Darkmoon FX |
//|                                        http://www.darkmoonfx.com |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2017, Darkmoon FX <http://www.darkmoonfx.com>"
#property link      "http://www.darkmoonfx.com"
#property version   "1.40"
#property strict

#property indicator_separate_window
#property indicator_buffers 3

#property indicator_color1 SteelBlue
#property indicator_width1 3

#property indicator_color2 Black
#property indicator_width2 3

#property indicator_color3 SkyBlue
#property indicator_width3 2


input string C0_1                = "========= Spread limits =========";
input double SpreadLowLevel      = 1.0;
input double SpreadHighLevel     = 2.0;

input string C0_2                = "========= Colors =========";
input color BGColor              = C'40, 40, 40';
input color SpreadNormalColor    = C'244,192,11';
input color SpreadRedColor       = C'203,78,78';
input color SpreadGreenColor     = C'133,202,128';
input color BarColor             = DimGray;

input string C1_0                = "========= Write to file =========";
input bool   WriteToCSV          = TRUE;




double      maxSpread[];
double      avgSpread[];
double      minSpread[];

double      spread         = 0.0;
double      sumSpread      = 0;
int         countSpread    = 0;
datetime    lastCandle     = 0;
double      pip_multiplier = 1.0;

string      FileName       = "";
static bool FirstRun       = TRUE;

//#include <IcePack.mqh>

int      windowIndex                   = 0;
string   objPrefix                     = "SpreadMonitor_";


string   IndiName                      = "SpreadMonitor v1.4.0";

/*******************  Version history  ********************************

   v1.4.0 - 2017.07.01
   --------------------
      - set global variables (MIN, MAX, AVG, CURR)
      
   v1.3.2 - 2016.03.13
   --------------------
      - fixed 2-digits XAU

   v1.3.1 - 2016.03.07
   --------------------
      - support 2-digits CFDs

   v1.3.0 - 2015.12.30
   --------------------
      - parameter of colors available

   v1.2.1 - 2014.01.30
   --------------------
      - Some bug fixed

   v1.1.0 - 2013.07.22
   --------------------
      - Date format in CSV filename bug fixed


   v1.1.0 - 2013.07.22
   --------------------
      - Write to CSV

   v1.0.1 - 2013.07.19
   --------------------
      - More usable levels


   v1.0.0 - 2013.07.18
   --------------------
      - First release

***********************************************************************/



//+------------------------------------------------------------------+
int OnInit()
//+------------------------------------------------------------------+
{
	IndicatorShortName(IndiName);
	
   SetIndexStyle(0, DRAW_HISTOGRAM, EMPTY, 3);
   IndicatorDigits(2);

   SetIndexBuffer       (0, maxSpread);
   SetIndexStyle        (0, DRAW_HISTOGRAM);
   SetIndexLabel        (0, "MaxSpread");	

   SetIndexBuffer       (1, minSpread);
   SetIndexStyle        (1, DRAW_HISTOGRAM);
   SetIndexLabel        (1, "MinSpread");	

   SetIndexBuffer       (2, avgSpread);
   SetIndexStyle        (2, DRAW_LINE, STYLE_SOLID, 2, Red);
   SetIndexLabel        (2, "Average Spread");	


   SetPipMultiplier();

   lastCandle  = iTime(NULL, 0, 0);
   sumSpread   = 0.0;
   countSpread = 0;
   
   FileName    = StringConcatenate("SpreadMonitor\\SpreadMonitor_", Symbol(), "_", Period(), "_Data.dat");


   SetLevelValue(1, 1);
   SetLevelValue(2, 3);
   SetLevelValue(3, 5);
   SetLevelValue(4, 10);
   SetLevelValue(5, 20);
   SetLevelValue(6, 40);
  
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
int start()
//+------------------------------------------------------------------+
{
   DoWork(); 

   return(0); 
}

//+------------------------------------------------------------------+
void DoWork()
//+------------------------------------------------------------------+
{
   windowIndex = WindowFind(IndiName);


   int counted_bars  = IndicatorCounted();   
   int limit         = Bars - counted_bars;

   /* 
   for(int i = limit; i > 0; i--)
   {
      spreadBuffer[i]   = EMPTY_VALUE;
      sumBuffer[i]      = EMPTY_VALUE;
      countBuffer[i]    = EMPTY_VALUE;
   } */
   
   if (FirstRun)
   {
      ReadSpreadFromFile(500);
      FirstRun = false;
   }  
   
   
   if (lastCandle != iTime(NULL, 0, 0))
   {
      WriteSpreadToFile(true);
   
      sumSpread   = 0;
      countSpread = 0;   
      
      lastCandle  = iTime(NULL, 0, 0);
   }

   spread = point2pip(Ask - Bid);
   SetGlobalVar("CURR", spread);
   
   sumSpread   += spread;
   countSpread += 1;
   
   if (spread > maxSpread[0] || maxSpread[0] == EMPTY_VALUE) {
      maxSpread[0] = spread;
      SetGlobalVar("MAX", spread);
   }
   
   if (spread < minSpread[0] || minSpread[0] == EMPTY_VALUE) {
      minSpread[0] = spread;
      SetGlobalVar("MIN", spread);
   }
   
   if (countSpread > 0) {
      avgSpread[0] = sumSpread / countSpread;
      SetGlobalVar("AVG", avgSpread[0]);
   }

   //Print("Spread: ", spread, ", sumSpread: ", sumSpread, ", countSpread: ", countSpread, ", avgSpread: ", avgSpread[0], ", minSpread: ", minSpread[0], ", maxSpread: ", maxSpread[0]);
   
   DrawDashboard();
   
   //DrawCurrentSpread();
   DrawAverageSpread();

   return;
}

//+------------------------------------------------------------------+
void SetGlobalVar(string name, double value) {
//+------------------------------------------------------------------+
   GlobalVariableSet(StringConcatenate("SPREAD_", StringSubstr(Symbol(), 0, 6), "_", Period(), "_", name), value);
}

//+------------------------------------------------------------------+
void DelGlobalVar(string name) {
//+------------------------------------------------------------------+
   GlobalVariableDel(StringConcatenate("SPREAD_", StringSubstr(Symbol(), 0, 6), "_", Period(), "_", name));
}

//+------------------------------------------------------------------+
void ReadSpreadFromFile(int maxBars)
//+------------------------------------------------------------------+
{
   double tempSum[];
   double tempCnt[];

   int f = FileOpen(FileName, FILE_BIN|FILE_READ);
   
   if (f <= 0) return;
   
   maxBars = MathMin(maxBars, 500);
   Print("Read spread info from file... (max ", maxBars, " bars)");

   int cnt = 0,
       oCnt = 0;
   
   ArrayResize(tempSum, maxBars);
   ArrayResize(tempCnt, maxBars);
   
   while (!FileIsEnding(f))
   {
      datetime time  = FileReadInteger(f);

      double max     = FileReadDouble(f);
      double avg     = FileReadDouble(f);
      double min     = FileReadDouble(f);

      double sum     = FileReadDouble(f);
      int    count   = FileReadInteger(f);
   
   
      int bar = iBarShift(Symbol(), Period(), time, TRUE);
      
      //Print("Read data: bar: ", bar, ", maxBars: ", maxBars, ", max: ", max, ", avg: ", avg, ", min: ", min, " sum: ", sum, ", count: ", count);
      if (bar >= 0 && bar < maxBars)
      {
         maxSpread[bar] = max;
         minSpread[bar] = min;
         
         avgSpread[bar] = avg;
         
         tempSum[bar]   = sum;
         tempCnt[bar]   = count;
         
         cnt++;
      }
      
      if (bar == 0)
      {
         sumSpread   = sum;
         countSpread = count;         
      }
   
      oCnt++;
   }

   FileClose(f);
   
   Print("Loaded ", cnt, " records from ", oCnt, ".");
   
   // Ha kétszer ennyi rekord van benne, akkor töröljük a régieket
   if (oCnt > maxBars * 2)
   {
      Print("There are too many records in the file! Refactoring...");
   
      FileDelete(FileName);
      
      f = FileOpen(FileName, FILE_BIN|FILE_READ|FILE_WRITE);
   
      FileSeek(f, 0, SEEK_SET);

      cnt = 0;
      for (int i = maxBars - 1; i >= 0; i--)
      {   
         if (avgSpread[i] != EMPTY_VALUE)
         {
            FileWriteInteger(f,  Time[i]);

            FileWriteDouble(f,   maxSpread[i]);
            FileWriteDouble(f,   avgSpread[i]);
            FileWriteDouble(f,   minSpread[i]);

            FileWriteDouble(f,   tempSum[i]);
            FileWriteInteger(f,  tempCnt[i]);
            
            cnt++;
         }
      }

      FileClose(f);   
      
      Print("Finished. New records: ", cnt);
   
   }
 
}

//+------------------------------------------------------------------+
void WriteSpreadToFile(bool newCandle)
//+------------------------------------------------------------------+
{
   int f = FileOpen(FileName, FILE_BIN|FILE_READ|FILE_WRITE);

   if (f <= 0) 
   {
      Print("File write error! Path: ", FileName);
      return;
   }
   
   FileSeek(f, 0, SEEK_END);
   
   FileWriteInteger(f, lastCandle);

   FileWriteDouble(f, maxSpread[1]);
   FileWriteDouble(f, avgSpread[1]);
   FileWriteDouble(f, minSpread[1]);

   FileWriteDouble(f, sumSpread);
   FileWriteInteger(f, countSpread);

   FileClose(f);
   
   
   if (WriteToCSV && newCandle)
   {
      string fileName = StringConcatenate("SpreadMonitor\\SpreadMonitor_", Symbol(), "_", Period(), "_", TimeYear(TimeCurrent()), LeadingZero(TimeMonth(TimeCurrent())), LeadingZero(TimeDay(TimeCurrent())), ".csv");
   
      f = FileOpen(fileName, FILE_CSV|FILE_READ|FILE_WRITE, ',');

      if (f <= 0) 
      {
         Print("File write error! Path: ", fileName);
         return;
      }
   
      FileSeek(f, 0, SEEK_END);
   
      if (FileSize(f) == 0)
         FileWrite(f, "Time", "MaxSpread", "AvgSpread", "MinSpread");
   
      FileWrite(f, TimeToStr(lastCandle, TIME_DATE|TIME_MINUTES), DTS(maxSpread[1], 1), DTS(avgSpread[1], 2), DTS(minSpread[1], 1));

      FileClose(f);
   }
}



//+------------------------------------------------------------------+
void DrawCurrentSpread()
//+------------------------------------------------------------------+
{
   string objName = objPrefix + "CurrentChartValue";
   
   if (ObjectFind(objName) != windowIndex) {
      ObjectCreate(objName, OBJ_HLINE, windowIndex, 0, 0);
      ObjectSet(objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSet(objName, OBJPROP_WIDTH, 1);
      ObjectSet(objName, OBJPROP_COLOR, Gray);
   }
   ObjectSet(objName, OBJPROP_PRICE1, spread);
}

//+------------------------------------------------------------------+
void DrawAverageSpread()
//+------------------------------------------------------------------+
{
   string objName = objPrefix + "ChartAverageSpreadValue";
   
   if (ObjectFind(objName) != windowIndex) {
      ObjectCreate(objName, OBJ_HLINE, windowIndex, 0, 0);
      ObjectSet(objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSet(objName, OBJPROP_WIDTH, 1);
      ObjectSet(objName, OBJPROP_COLOR, SkyBlue);
   }
   ObjectSet(objName, OBJPROP_PRICE1, avgSpread[0]);
}


//+------------------------------------------------------------------+
int deinit()
//+------------------------------------------------------------------+
{
   WriteSpreadToFile(false);
   
   DeleteAllObject(objPrefix);
   
   DelGlobalVar("CURR");
   DelGlobalVar("AVG");
   DelGlobalVar("MIN");
   DelGlobalVar("MAX");

   return(0);
}

//+------------------------------------------------------------------+
void DrawCopyright()
//+------------------------------------------------------------------+
{
   string text = "http://darkmoonfx.com"; 
   DrawText(objPrefix + "XDCopy", 1, 15, 113, text, DimGray, 7);
}

//+------------------------------------------------------------------+
void DrawDashboard()
//+------------------------------------------------------------------+
{
   string name = objPrefix + "XD";

   DrawBackground(name + ".BG", 1, 2, 5, BGColor, 90);

   string sMax = ifs(maxSpread[0] != EMPTY_VALUE, DTS(maxSpread[0], 1), '-');
   string sMin = ifs(minSpread[0] != EMPTY_VALUE, DTS(minSpread[0], 1), '-');

   // Draw maximum spread
   color c = getSpreadColor(maxSpread[0]);   
   DrawText(name, 1, 40, 5, "Maximum", Silver, 7);
   DrawText(name, 1, 50, 15, sMax, c, 11);

   // Draw maximum spread
   c = getSpreadColor(spread);   
   DrawText(name, 1, 45, 40, "Current", Silver);
   DrawText(name, 1, 40, 45, DTS(spread, 1), c, 20, "Arial Black");


   // Draw maximum spread
   c = getSpreadColor(minSpread[0]);   
   DrawText(name, 1, 40, 85, "Minimum", Silver, 7);
   DrawText(name, 1, 50, 95, sMin, c, 10);


   // Draw spread range bar
   if (maxSpread[0] != EMPTY_VALUE && minSpread[0] != EMPTY_VALUE)
   {
      int x    = 10,
          y    = 1,
          step = 3,
          barCount = 24;  
       
      double spreadRange = maxSpread[0] - minSpread[0];
      double rangeStep = spreadRange / 24;
   
      color bgC = BarColor;
      c = bgC;
      
      
      for (int i = 0; i < barCount; i++)
      {
         double barSpread = minSpread[0] + (barCount - i) * rangeStep;
         
         if ((spread >= barSpread) || (i == barCount - 1)) // last green always light
            c = getSpreadColor(barSpread);
         else 
            c = bgC;
         
         DrawText(name, 1, x, y + step * i, "-", c, 20, "Arial", false);
      }
   }
   
   DrawCopyright();

}

//+------------------------------------------------------------------+
string LeadingZero(int n)
//+------------------------------------------------------------------+
{
	if (n <= 9) 
		return("0"+n);
	else
		return(n);
}


//+------------------------------------------------------------------+
color getSpreadColor(double spread)
//+------------------------------------------------------------------+
{
   if (spread >= SpreadHighLevel)
      return(SpreadRedColor);
   else if (spread <= SpreadLowLevel)
      return(SpreadGreenColor);
   else
      return(SpreadNormalColor);

}

//+------------------------------------------------------------------+
void DrawBackground(string name, int corner, int X, int Y, color c, int size = 180, string ch = "g")
//+------------------------------------------------------------------+
{
   if (name == "") name = "BKGR";
   
   if (ObjectFind(name) < 0) {
      ObjectCreate(name, OBJ_LABEL, windowIndex, 0, 0);
      ObjectSet(name, OBJPROP_BACK, false);
   }   
   ObjectSet(name, OBJPROP_CORNER, corner);
   ObjectSet(name, OBJPROP_XDISTANCE, X);
   ObjectSet(name, OBJPROP_YDISTANCE, Y);
   ObjectSetText(name, ch, size, "Webdings", c);
}

//+------------------------------------------------------------------+
string DrawText(string prefix, int corner, int X, int Y, string text, color c, int size = 7, string customFont = "", bool drawShadow = true) 
//+------------------------------------------------------------------+
{
   string font = "Tahoma"; if(customFont != "") font = customFont;
    
   if (drawShadow)
      DrawText(prefix, corner, X - 1, Y + 1, text, Black, size, font, false);
    
   string objName = StringConcatenate(prefix, corner, ifs(drawShadow, "T", "S"), "_", X, "_", Y);
   if (ObjectFind(objName) != 0) {
      ObjectCreate(objName, OBJ_LABEL, windowIndex, 0, 0);
      ObjectSet(objName, OBJPROP_CORNER, corner);
   }

   ObjectSetText(objName, text, size, font, c);
   ObjectSet(objName, OBJPROP_XDISTANCE, X);
   ObjectSet(objName, OBJPROP_YDISTANCE, Y);
   ObjectSet(objName, OBJPROP_BACK, false);
   
   return(objName);
}

//+------------------------------------------------------------------+
void DeleteAllObject(string prefix = "")
//+------------------------------------------------------------------+
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
      if(prefix == "" || StringFind(ObjectName(i), prefix, 0) >= 0)
         ObjectDelete(ObjectName(i));

}

double SetPipMultiplier(bool simple = false) 
{
   pip_multiplier = 1;
   
   if (simple)
   {
      if (Digits % 4 != 0) pip_multiplier = 10; 
        
   } else {
      if (Digits == 5 || 
         (Digits == 3 && StringFind(Symbol(), "JPY") > -1) ||     // Ha 3 digites és JPY
         (Digits == 2 && StringFind(Symbol(), "XAU") > -1) ||     // Ha 2 digites és arany
         (Digits == 2 && StringFind(Symbol(), "GOLD") > -1) ||    // Ha 2 digites és arany
         (Digits == 3 && StringFind(Symbol(), "XAG") > -1) ||     // Ha 3 digites és ezüst
         (Digits == 3 && StringFind(Symbol(), "SILVER") > -1) ||  // Ha 3 digites és ezüst
         (Digits == 1))                                           // Ha 1 digit (CFDs)
            pip_multiplier = 10;
      else if (Digits == 6 || 
         (Digits == 4 && StringFind(Symbol(), "JPY") > -1) ||     // Ha 4 digites és JPY
         (Digits == 3 && StringFind(Symbol(), "XAU") > -1) ||     // Ha 3 digites és arany
         (Digits == 3 && StringFind(Symbol(), "GOLD") > -1) ||    // Ha 3 digites és arany
         (Digits == 4 && StringFind(Symbol(), "XAG") > -1) ||     // Ha 4 digites és ezüst
         (Digits == 4 && StringFind(Symbol(), "SILVER") > -1) ||  // Ha 4 digites és ezüst
         (Digits == 2))                                           // Ha 2 digit (CFDs)
            pip_multiplier = 100;
   }  
   //Print("PipMultiplier: ", pip_multiplier, ", Digits: ", Digits);
   return(pip_multiplier);
}

double pip2point(double pip)
{
   return (pip * Point * pip_multiplier);
}

double point2pip(double point)
{
   return(point / Point / pip_multiplier);
}

string DTS(double value, int decimal = 0) { return(DoubleToStr(value, decimal)); }

string ifs(bool state, string val1, string val2)
{
   if (state)
      return(val1);
   else
      return(val2);
}

int ifi(bool state, int val1, int val2)
{
   if (state)
      return(val1);
   else
      return(val2);
}

double ifd(bool state, double val1, double val2)
{
   if (state)
      return(val1);
   else
      return(val2);
}
