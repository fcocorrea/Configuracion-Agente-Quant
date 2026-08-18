//+------------------------------------------------------------------+
//|                                                  ea_template.mq5 |
//|      Plantilla base POO: filtro volumen + RSI + cierre de vela  |
//+------------------------------------------------------------------+
#property copyright "Plantilla EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs generales
input double InpLots            = 0.10;    // Lotaje fijo (ajustar a gestión de riesgo real)
input int    InpMagicNumber     = 123456;  // Magic number
input int    InpSlippage        = 10;      // Slippage en puntos
input double InpStopLossPoints  = 500;     // Stop loss en puntos (0 = sin SL)
input double InpTakeProfitPoints= 1000;    // Take profit en puntos (0 = sin TP)

//--- Inputs filtro volumen
input int    InpVolumePeriod    = 20;      // Velas para el promedio de volumen

//--- Inputs filtro RSI
input int    InpRsiPeriod       = 14;      // Período del RSI
input double InpRsiOverbought   = 70.0;    // Nivel de sobrecompra
input double InpRsiOversold     = 30.0;    // Nivel de sobreventa

//+------------------------------------------------------------------+
//| CBarMonitor: detecta el cierre de una vela nueva                |
//+------------------------------------------------------------------+
class CBarMonitor
  {
private:
   datetime m_lastBarTime;

public:
                     CBarMonitor(void) : m_lastBarTime(0) {}

   //--- true una única vez por vela nueva cerrada
   bool              IsNewBar(void)
     {
      datetime currentBarTime = iTime(_Symbol, _Period, 0);
      if(currentBarTime == m_lastBarTime)
         return false;

      m_lastBarTime = currentBarTime;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| CSignalFilter: filtro obligatorio de volumen + RSI               |
//| Encapsula las 3 reglas por defecto (volumen, RSI, cierre vela   |
//| se gestiona vía CBarMonitor desde el EA principal).              |
//+------------------------------------------------------------------+
class CSignalFilter
  {
private:
   int               m_rsiHandle;
   int               m_volumePeriod;
   double            m_rsiOverbought;
   double            m_rsiOversold;

   //--- Volumen de la vela shift (1 = última vela cerrada)
   bool              GetVolume(int shift, long &volumeOut)
     {
      long volumeBuffer[];
      ArraySetAsSeries(volumeBuffer, true);

      if(CopyTickVolume(_Symbol, _Period, shift, 1, volumeBuffer) <= 0)
        {
         Print(__FUNCTION__, ": error copiando volumen, code=", GetLastError());
         return false;
        }

      volumeOut = volumeBuffer[0];
      return true;
     }

   //--- Promedio de volumen de las N velas previas a 'shift' (excluye 'shift')
   bool              GetAverageVolume(int shift, int period, double &avgOut)
     {
      long volumeBuffer[];
      ArraySetAsSeries(volumeBuffer, true);

      if(CopyTickVolume(_Symbol, _Period, shift + 1, period, volumeBuffer) <= 0)
        {
         Print(__FUNCTION__, ": error copiando volumen promedio, code=", GetLastError());
         return false;
        }

      long sum = 0;
      int  count = ArraySize(volumeBuffer);
      for(int i = 0; i < count; i++)
         sum += volumeBuffer[i];

      if(count == 0)
         return false;

      avgOut = (double)sum / (double)count;
      return true;
     }

   //--- RSI de la vela shift
   bool              GetRsi(int shift, double &rsiOut)
     {
      double rsiBuffer[];
      ArraySetAsSeries(rsiBuffer, true);

      if(CopyBuffer(m_rsiHandle, 0, shift, 1, rsiBuffer) <= 0)
        {
         Print(__FUNCTION__, ": error copiando RSI, code=", GetLastError());
         return false;
        }

      rsiOut = rsiBuffer[0];
      return true;
     }

public:
                     CSignalFilter(void) : m_rsiHandle(INVALID_HANDLE),
                                            m_volumePeriod(20),
                                            m_rsiOverbought(70.0),
                                            m_rsiOversold(30.0) {}

   bool              Init(int rsiPeriod, double rsiOverbought, double rsiOversold, int volumePeriod)
     {
      m_volumePeriod  = volumePeriod;
      m_rsiOverbought = rsiOverbought;
      m_rsiOversold   = rsiOversold;

      m_rsiHandle = iRSI(_Symbol, _Period, rsiPeriod, PRICE_CLOSE);
      if(m_rsiHandle == INVALID_HANDLE)
        {
         Print(__FUNCTION__, ": no se pudo crear el handle de RSI, code=", GetLastError());
         return false;
        }

      return true;
     }

   void              Deinit(void)
     {
      if(m_rsiHandle != INVALID_HANDLE)
         IndicatorRelease(m_rsiHandle);
     }

   //--- Regla 1: volumen de la última vela cerrada > promedio de las 20 previas
   bool              IsVolumeConfirmed(void)
     {
      long   lastVolume  = 0;
      double avgVolume   = 0.0;

      if(!GetVolume(1, lastVolume))
         return false;
      if(!GetAverageVolume(1, m_volumePeriod, avgVolume))
         return false;

      return (double)lastVolume > avgVolume;
     }

   //--- Regla 2: filtro RSI direccional.
   //--- Nunca comprar en sobrecompra, nunca vender en sobreventa.
   //--- Comprar en sobreventa o vender en sobrecompra SÍ está permitido.
   bool              IsRsiAllowed(int direction)
     {
      double rsi = 0.0;
      if(!GetRsi(1, rsi))
         return false;

      if(direction == 1 && rsi >= m_rsiOverbought)   // compra bloqueada en sobrecompra
         return false;
      if(direction == -1 && rsi <= m_rsiOversold)    // venta bloqueada en sobreventa
         return false;

      return true;
     }

   //--- Filtro combinado obligatorio: se debe llamar antes de cualquier entrada,
   //--- ya con la dirección propuesta por la señal (1 compra, -1 venta).
   bool              IsAllowedToTrade(int direction)
     {
      return IsVolumeConfirmed() && IsRsiAllowed(direction);
     }

   //--- Placeholder: reemplazar por la señal direccional real de la estrategia.
   //--- El filtro de volumen/RSI/cierre-de-vela es una capa previa, no la señal.
   int               GetDirection(void)
     {
      // return 1 (compra), -1 (venta), 0 (sin señal)
      return 0;
     }
  };

//+------------------------------------------------------------------+
//| CExpertAdvisor: orquesta filtros + ejecución con CTrade          |
//+------------------------------------------------------------------+
class CExpertAdvisor
  {
private:
   CTrade            m_trade;
   CBarMonitor       m_barMonitor;
   CSignalFilter     m_filter;

   double            m_lots;
   double            m_slPoints;
   double            m_tpPoints;

   bool              OpenPosition(ENUM_ORDER_TYPE orderType)
     {
      double price = (orderType == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double sl = 0.0, tp = 0.0;

      if(m_slPoints > 0)
         sl = (orderType == ORDER_TYPE_BUY) ? price - m_slPoints * point
                                             : price + m_slPoints * point;
      if(m_tpPoints > 0)
         tp = (orderType == ORDER_TYPE_BUY) ? price + m_tpPoints * point
                                             : price - m_tpPoints * point;

      bool result = (orderType == ORDER_TYPE_BUY)
                    ? m_trade.Buy(m_lots, _Symbol, price, sl, tp)
                    : m_trade.Sell(m_lots, _Symbol, price, sl, tp);

      if(!result)
        {
         Print(__FUNCTION__, ": fallo al enviar orden, retcode=", m_trade.ResultRetcode(),
               " desc=", m_trade.ResultRetcodeDescription());
        }

      return result;
     }

public:
   bool              Init(int magicNumber, int slippage, double lots,
                           double slPoints, double tpPoints,
                           int rsiPeriod, double rsiOverbought, double rsiOversold,
                           int volumePeriod)
     {
      m_lots     = lots;
      m_slPoints = slPoints;
      m_tpPoints = tpPoints;

      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);

      return m_filter.Init(rsiPeriod, rsiOverbought, rsiOversold, volumePeriod);
     }

   void              Deinit(void)
     {
      m_filter.Deinit();
     }

   //--- Regla 3: toda la lógica de señal se evalúa una sola vez por vela nueva
   void              OnTick(void)
     {
      if(!m_barMonitor.IsNewBar())
         return;

      if(PositionSelect(_Symbol))
         return; // ya hay posición abierta en este símbolo; gestión de salida queda fuera del alcance de esta plantilla

      int direction = m_filter.GetDirection();
      if(direction == 0)
         return;

      if(!m_filter.IsAllowedToTrade(direction))
         return;

      if(direction == 1)
         OpenPosition(ORDER_TYPE_BUY);
      else if(direction == -1)
         OpenPosition(ORDER_TYPE_SELL);
     }
  };

CExpertAdvisor g_ea;

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if(!g_ea.Init(InpMagicNumber, InpSlippage, InpLots,
                  InpStopLossPoints, InpTakeProfitPoints,
                  InpRsiPeriod, InpRsiOverbought, InpRsiOversold,
                  InpVolumePeriod))
     {
      Print("Error inicializando el EA");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_ea.Deinit();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_ea.OnTick();
  }
//+------------------------------------------------------------------+
