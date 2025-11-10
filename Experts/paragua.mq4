//+------------------------------------------------------------------+
//|                                                       Paragua.mq4 |
//|                        Basado en Account Protector de EarnForex   |
//|                                  Versión especializada para XAUUSD|
//+------------------------------------------------------------------+
#property copyright "Adaptación especializada para estrategias grid en XAUUSD"
#property link      "https://github.com/EarnForex/Account-Protector"
#property version   "1.00"
#property strict

// Parámetros configurables
input double   EquityThreshold = 85.0;    // % de equity sobre balance para activación
input int      MinDuration = 3;           // Minutos de persistencia para activación
input double   MaxSpread = 25.0;          // Spread máximo en pips para display
input int      MA_Period_Short = 50;      // Periodo corto para cambio de tendencia
input int      MA_Period_Long = 200;      // Periodo largo para cambio de tendencia
input int      Magic_Number = 3030;       // Magic number para las órdenes del protector
input string   SoundFile = "alert.wav";   // Archivo de sonido para alarma
input int      TimerInterval = 60;        // Segundos entre ejecuciones de OnTimer()

// Parámetros para cálculo de lote
input double   LoteMinimo = 0.01;         // Lote mínimo permitido
input double   LoteMaximo = 0.50;         // Lote máximo permitido
input double   FactorPosiciones = 0.001;  // Multiplicador por posición
input double   FactorEquity = 0.001;      // Multiplicador por equity

// Parámetros para reintentos
input int      MaxReintentosOrden = 5;    // Máximo reintentos para órdenes
input int      MaxReintentosCierre = 3;   // Máximo reintentos para cierre gráficos

// NUEVOS PARÁMETROS PARA DETECCIÓN MEJORADA
input int      MA_Period_Rapida = 15;                    // EMA rápida para M5
input int      MA_Period_Lenta = 50;                     // EMA lenta para M5  
input double   MaxDrawdownProtector = 10.0;              // % drawdown para activación (default 10%)
input int      TiempoConfirmacionDrawdown = 60;          // Segundos para confirmar drawdown (default 60)

// Parámetros para backtesting
input bool     Modo_Backtest = false;           // Activar modo backtesting
input datetime Fecha_Inicio_Backtest = D'2023.01.01'; // Fecha inicio backtest
input datetime Fecha_Fin_Backtest = D'2023.12.31';   // Fecha fin backtest

// Variables globales
bool           InWaitingState = false;
datetime       TimerStart = 0;
int            RecoveryCount = 0;
bool           WasBelowThreshold = false;
int            CurrentOpenPositions = 0;
int            MaxHistoricPositions = 0;
double         MaxHistoricLoss = 0.0;
double         MaxHistoricSpread = 0.0;

// MODIFICACIÓN 2: NUEVAS VARIABLES PARA EL PEOR ESCENARIO HISTÓRICO
double         MaxDrawdownHistoric = 0.0;        // Máximo drawdown histórico en %
double         BalanceAtMaxDrawdown = 0.0;       // Balance en el peor momento
double         LoteMaxAtMaxDrawdown = 0.0;       // Lote máximo calculado en peor escenario

// NUEVAS VARIABLES PARA CONTROL DE INTENTOS
int            IntentosCierreFallidos = 0;
const int      MaxIntentosCierreFallidos = 5;

// Nuevas variables para la lógica de cobertura
bool           ModoProteccionActivado = false;
int            DireccionEAPrincipal = -1;
double         LoteFijo = 0.0;
double         UltimoEscalon = 0.0;
double         PisoActual = 0.0;
bool           GraficoCerrado = false;

// Variables de episodio
int            EpisodioDireccion = -1;
double         EpisodioLoteBase = 0.0;
double         EpisodioUltimoEscalon = 0.0;
double         EpisodioPisoActual = 0.0;  // 🆕 NUEVA VARIABLE PARA PISO RECALIBRADO
datetime       EpisodioInicio = 0;

// NUEVA VARIABLE PARA DRAWDOWN
datetime       TiempoInicioDrawdown = 0;

// Colores para el panel - CORREGIDOS para MQL4
const color    COLOR_POSITIONS = 0x007FFF;    // Azul
const color    COLOR_LOSS = clrRed;
const color    COLOR_RECOVERY = clrYellow;
const color    COLOR_SPREAD = clrCyan;
const color    COLOR_MAX_VALUES = clrWhite;
const color    COLOR_MARGEN = clrLawnGreen;
const color    PANEL_BG = 0x1A1A1A;           // Gris oscuro

// NUEVAS VARIABLES PARA MANEJO DE SÍMBOLOS
string SymbolXAU = "";  // Símbolo normalizado para XAUUSD
string TradingSymbol = ""; // Símbolo real para trading

// Variable para bloquear nuevas aperturas durante el cierre
bool BloqueoPorCierre = false;

// Variables para período de reflexión
datetime UltimoCierreTendencia = 0;
const int PeriodoReflexionHoras = 12; // 12 horas = 3 velas H4

// Variables para backtesting
int    Backtest_Señales_Generadas = 0;
int    Backtest_Señales_Accionadas = 0;
int    Backtest_Coberturas_Abiertas = 0;
int    Backtest_Coberturas_Cerradas = 0;
double Backtest_Ganancia_Neta = 0.0;
double Backtest_Max_Drawdown = 0.0;

// ✅ AGREGAR PARÁMETRO DE CONFIGURACIÓN Notificaciones
input bool     Habilitar_Notificaciones = false;  // Enviar emails/notificaciones?
input bool     Habilitar_Alertas_Sonido = true;   // Reproducir sonidos de alerta?

//+------------------------------------------------------------------+
//| Función de inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // Inicializar símbolo normalizado
   SymbolXAU = NormalizeSymbol("XAUUSD");
   TradingSymbol = GetTradingSymbol();
   
   Print("Símbolo normalizado: " + SymbolXAU);
   Print("Símbolo trading: " + TradingSymbol);
   
   LoadPersistentData();
   CreateMonitoringPanel();
   EventSetTimer(TimerInterval);
   
   int handle = FileOpen(SoundFile, FILE_READ);
   if(handle == INVALID_HANDLE) {
       FileClose(handle);
       // Archivo no existe
   } 
      Print("Advertencia: Archivo de sonido no encontrado");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Función de desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SavePersistentData();
   DeleteMonitoringPanel();
   EventKillTimer();
   
   // 🆕 Generar reporte de backtesting si está activo
   if(Modo_Backtest) {
      GenerarReporteBacktesting();
   }
}

//+------------------------------------------------------------------+
//| Función de timer para ejecución garantizada                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Ejecutar monitoreo principal incluso sin ticks
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   
   MonitoreoPrincipal(equityPercent, spread);
   
   // 🆕 VERIFICACIÓN CONTINUA DE RECUPERACIÓN
   VerificarRecuperacionEquity(equityPercent);
   
   UpdateAllChartsPanels(equityPercent, spread);
}

//+------------------------------------------------------------------+
//| Función principal de tick                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   CurrentOpenPositions = CountOpenPositions();
   
   MonitoreoPrincipal(equityPercent, spread);
   
   // 🆕 VERIFICACIÓN CONTINUA DE RECUPERACIÓN
   VerificarRecuperacionEquity(equityPercent);
   
   UpdateAllChartsPanels(equityPercent, spread);
}

//+------------------------------------------------------------------+
//| Verificación continua de recuperación de equity (NUEVA)         |
//+------------------------------------------------------------------+
void VerificarRecuperacionEquity(double equityPercent)
{
    if(ModoProteccionActivado && equityPercent > EquityThreshold)
    {
        Print("✅ EQUITY RECUPERADO - Volviendo a modo vigilia");
        DesactivarModoProteccion();
    }
}

//+------------------------------------------------------------------+
//| Monitoreo principal - Lógica común para OnTick y OnTimer         |
//+------------------------------------------------------------------+
void MonitoreoPrincipal(double equityPercent, double spread)
{
   // Detectar recuperaciones
   if(equityPercent <= EquityThreshold)
      WasBelowThreshold = true;
   else if(WasBelowThreshold)
   {
      RecoveryCount++;
      GlobalVariableSet("Protector_RecoveryCount", RecoveryCount);
      WasBelowThreshold = false;
   }
   
   UpdateHistoricalTrackers(equityPercent, spread);
   
   if(!ModoProteccionActivado)
      CheckActivationConditions(equityPercent);
   else
      ManageProtectionMode(equityPercent);
}

//+------------------------------------------------------------------+
//| Verificar condiciones de activación (MODIFICADA)                |
//+------------------------------------------------------------------+
void CheckActivationConditions(double equityPercent)
{
   // 🆕 COMPORTAMIENTO ROBUSTO DEL TEMPORIZADOR
   if(InWaitingState)
   {
      // Temporizador en progreso - verificar si completó
      if(TimeCurrent() - TimerStart >= MinDuration * 60)
      {
         ActivarModoProteccion();
      }
      // 🆕 NO cancelar aunque equity se recupere temporalmente
      return;
   }
   
   if(equityPercent > EquityThreshold)
   {
      // No hacer nada si equity está por encima del umbral
      return;
   }
   
   // NUEVA LÓGICA: Verificar estado del gráfico
   if(!IsXAUUSDChartOpen()) 
   {
      // GRÁFICO CERRADO → Activación inmediata
      ActivarModoProteccion();
      return;
   }
   
   // GRÁFICO ABIERTO → Lógica de espera
   if(!InWaitingState)
   {
      TimerStart = TimeCurrent();
      InWaitingState = true;
      Print("Iniciando temporizador de protección...");
   }
}

//+------------------------------------------------------------------+
//| Verificar si hay gráficos XAUUSD abiertos (NUEVA)               |
//+------------------------------------------------------------------+
bool IsXAUUSDChartOpen()
{
   long chartId = ChartFirst();
   int chartsFound = 0;
   
   while(chartId >= 0)
   {
      string chartSymbol = ChartSymbol(chartId);
      if(NormalizeSymbol(chartSymbol) == SymbolXAU)
         chartsFound++;
      chartId = ChartNext(chartId);
   }
   
   return (chartsFound > 0);
}

//+------------------------------------------------------------------+
//| Activar modo protección                                          |
//+------------------------------------------------------------------+
void ActivarModoProteccion()
{
   // 1. Detectar dirección del EA principal
   if(!DetectarDireccionEAPrincipal())
   {
      Print("Error: No se pudo detectar la dirección del EA principal");
      return;
   }
   
   // 2. Cerrar gráfico XAUUSD con reintentos (solo si está abierto)
   if(IsXAUUSDChartOpen())
   {
      if(!CerrarGraficoXAUUSDConReintentos())
      {
         Print("Error: No se pudieron cerrar todos los gráficos XAUUSD");
         return;
      }
   }
   
   // 3. Calcular lote inicial
   CalcularLoteInicial();
   
   // 4. Establecer piso inicial
   double equity = AccountEquity();
   double balance = AccountBalance();
   PisoActual = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   UltimoEscalon = PisoActual;
   
   // 5. Guardar variables del episodio
   GuardarEpisodio();
   
   // 6. Abrir primera cobertura
   if(!AbrirCoberturaConReintentos())
   {
      Print("Error: No se pudo abrir la cobertura inicial");
      return;
   }
   
   // 7. Activar modo protección
   ModoProteccionActivado = true;
   InWaitingState = false;
   TimerStart = 0;
   GraficoCerrado = true;
   
   // 8. Notificar
   string direccion = (DireccionEAPrincipal == OP_BUY) ? "BUY" : "SELL";
   string mensaje = StringFormat("MODO PROTECCIÓN ACTIVADO - Dirección EA: %s - Lote: %.3f - Piso: %.2f%%", 
                                direccion, LoteFijo, PisoActual);
   
   SendNotifications(mensaje);
   PlayAlarmSound();
   Print(mensaje);
}

//+------------------------------------------------------------------+
//| Gestionar modo protección activo (MODIFICADA CON BLOQUEO)       |
//+------------------------------------------------------------------+
void ManageProtectionMode(double equityPercent)
{
   // Si estamos en proceso de cierre, no hacer nada
   if(BloqueoPorCierre)
   {
      Print("🔒 Bloqueo activo - Procesando cierre, no se abren nuevas coberturas");
      return;
   }

   // Verificar cambio de tendencia para cerrar coberturas
   if(DebeCerrarCoberturas())
   {
      Print("🚨 Condición de cierre detectada - Activando bloqueo");
      BloqueoPorCierre = true; // 🆕 ACTIVAR BLOQUEO

      if(!CerrarCoberturasConReintentos())
      {
         IntentosCierreFallidos++;
         Print(StringFormat("Intento fallido #%d de cerrar coberturas", IntentosCierreFallidos));
         
         if(IntentosCierreFallidos >= MaxIntentosCierreFallidos)
         {
            Print("MÁXIMO DE INTENTOS FALLIDOS ALCANZADO - Activando Plan B");
            ActivarPlanB();
            BloqueoPorCierre = false; // 🆕 DESBLOQUEAR INCLUSO EN FALLO
         }
         else
         {
            BloqueoPorCierre = false; // 🆕 DESBLOQUEAR PARA REINTENTAR MÁS TARDE
         }
      }
      else
      {
         // Éxito - resetear contador y continuar con lógica post-cierre
         IntentosCierreFallidos = 0;
         AfterCoberturasClosed(equityPercent);
         BloqueoPorCierre = false; // 🆕 DESBLOQUEAR DESPUÉS DEL CIERRE
         return;
      }
   }
   
   // MODIFICACIÓN 1: Lógica de nuevas coberturas escalonadas CON ESCALONAMIENTO EXACTO
   if(equityPercent <= UltimoEscalon - 1.0)
   {
      if(AbrirCoberturaConReintentos())
      {
         // MODIFICACIÓN CRÍTICA: Escalón exacto del 1%
         UltimoEscalon = UltimoEscalon - 1.0;  // ← GARANTIZA 76%, 75%, 74% exactos
         Print(StringFormat("Nueva cobertura abierta en: %.2f%% - Próximo escalón: %.2f%%", 
                           equityPercent, UltimoEscalon));
      }
   }
}

//+------------------------------------------------------------------+
//| Lógica después de cerrar coberturas (NUEVA)                     |
//+------------------------------------------------------------------+
void AfterCoberturasClosed(double equityPercent)
{
   // Verificar si equity se recuperó por debajo del umbral
   if(equityPercent > EquityThreshold)
   {
      // Equity recuperado → Desactivar protección
      DesactivarModoProteccion();
   }
   else
   {
      // Equity aún crítico → Verificar estado del gráfico
      if(IsXAUUSDChartOpen())
      {
         // Gráfico ABIERTO → Volver a modo vigía
         DesactivarModoProteccion();
      }
      else
      {
         // Gráfico CERRADO → Recalibrar y continuar protección
         PisoActual = equityPercent;
         UltimoEscalon = equityPercent;
         
         // Reabrir cobertura inicial
         if(AbrirCoberturaConReintentos())
         {
            string mensaje = StringFormat("PROTECCIÓN RECALIBRADA - Nuevo piso: %.2f%%", PisoActual);
            SendNotifications(mensaje);
            Print(mensaje);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFICACIÓN: Nueva función de cierre dual                      |
//+------------------------------------------------------------------+
bool DebeCerrarCoberturas()
{
   // Condición 1: Drawdown protector >= 10% por 60 segundos
   bool drawdownConfirmado = DrawdownProtectorConfirmado(MaxDrawdownProtector, TiempoConfirmacionDrawdown);
   
   // Condición 2: Tendencia H4 confirmada (5 filtros)
   bool tendenciaConfirmada = TendenciaH4Confirmada();
   
   // Cerrar si se cumple alguna de las dos condiciones
   if(drawdownConfirmado || tendenciaConfirmada)
   {
      string motivo = drawdownConfirmado ? "Drawdown 10%" : "Cambio tendencia H4";
      Print("🚨 CIERRE ACTIVADO - Motivo: " + motivo);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Drawdown con confirmación temporal (NUEVA)                      |
//+------------------------------------------------------------------+
bool DrawdownProtectorConfirmado(double porcentaje, int segundos)
{
   double drawdownActual = CalcularDrawdownProtector();
   
   if(drawdownActual >= porcentaje) {
      if(TiempoInicioDrawdown == 0) {
         TiempoInicioDrawdown = TimeCurrent();
         Print("Drawdown crítico detectado: " + DoubleToString(drawdownActual, 1) + "%. Esperando confirmación...");
      }
      else if(TimeCurrent() - TiempoInicioDrawdown >= segundos) {
         TiempoInicioDrawdown = 0;
         return true;
      }
   } else {
      // Resetear si el drawdown mejora
      if(TiempoInicioDrawdown != 0) {
         Print("Drawdown mejoró. Cancelando confirmación.");
         TiempoInicioDrawdown = 0;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Calcular drawdown solo del protector (NUEVA)                    |
//+------------------------------------------------------------------+
double CalcularDrawdownProtector()
{
   double maxProfit = 0;
   double currentProfit = 0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU && 
            OrderMagicNumber() == Magic_Number) {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            currentProfit += profit;
            if(profit > maxProfit) maxProfit = profit;
         }
      }
   }
   
   if(maxProfit > 0 && currentProfit < maxProfit) {
      return ((maxProfit - currentProfit) / maxProfit) * 100;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Activar plan B mejorado (MODIFICADA)                            |
//+------------------------------------------------------------------+
void ActivarPlanB()
{
   string mensaje = "PLAN B ACTIVADO - Fallo crítico en el protector";
   SendNotifications(mensaje);
   Alert(mensaje);
   
   // 1. Forzar cierre de emergencia (con mayor slippage)
   Print("EJECUTANDO CIERRE DE EMERGENCIA...");
   CierreEmergenciaCoberturas();
   
   // 2. Desactivar modo protección COMPLETAMENTE
   ModoProteccionActivado = false;
   InWaitingState = false;
   TimerStart = 0;
   GraficoCerrado = false;
   IntentosCierreFallidos = 0;
   TiempoInicioDrawdown = 0;
   
   // 3. Resetear episodio
   ResetearEpisodio();
   
   // 4. Notificar estado final
   Print("MODO PROTECCIÓN DESACTIVADO POR FALLO CRÍTICO - Intervención manual requerida");
}

//+------------------------------------------------------------------+
//| Cierre de emergencia (NUEVA)                                    |
//+------------------------------------------------------------------+
void CierreEmergenciaCoberturas()
{
   int cerradas = 0;
   int total = 0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU && 
            OrderMagicNumber() == Magic_Number)
         {
            total++;
            double precioCierre = (OrderType() == OP_BUY) ? MarketInfo(TradingSymbol, MODE_BID) : MarketInfo(TradingSymbol, MODE_ASK);
            
            GetLastError(); // 🆕 EVITA PROPAGACIÓN DE ERRORES
            // Cierre con mayor slippage (10 vs 3 normal)
            if(OrderClose(OrderTicket(), OrderLots(), precioCierre, 10, clrNONE))
               cerradas++;
         }
      }
   }
   
   Print(StringFormat("CIERRE EMERGENCIA: %d/%d coberturas cerradas", cerradas, total));
}

//+------------------------------------------------------------------+
//| Guardar variables del episodio (MODIFICADA)                     |
//+------------------------------------------------------------------+
void GuardarEpisodio()
{
   EpisodioDireccion = DireccionEAPrincipal;
   EpisodioLoteBase = LoteFijo;
   EpisodioUltimoEscalon = UltimoEscalon;
   EpisodioPisoActual = PisoActual;  // 🆕 GUARDAR PISO RECALIBRADO
   EpisodioInicio = TimeCurrent();
   
   GlobalVariableSet("Protector_EpisodioDireccion", EpisodioDireccion);
   GlobalVariableSet("Protector_EpisodioLoteBase", EpisodioLoteBase);
   GlobalVariableSet("Protector_EpisodioUltimoEscalon", EpisodioUltimoEscalon);
   GlobalVariableSet("Protector_EpisodioPisoActual", EpisodioPisoActual);  // 🆕 NUEVA LÍNEA
   GlobalVariableSet("Protector_EpisodioInicio", EpisodioInicio);
}

//+------------------------------------------------------------------+
//| Resetear variables del episodio (MODIFICADA)                    |
//+------------------------------------------------------------------+
void ResetearEpisodio()
{
   EpisodioDireccion = -1;
   EpisodioLoteBase = 0.0;
   EpisodioUltimoEscalon = 0.0;
   EpisodioPisoActual = 0.0;  // 🆕 NUEVA LÍNEA
   EpisodioInicio = 0;
   
   // 🆕 RESET COMPLETO DE VARIABLES DE ESCALONAMIENTO
   UltimoEscalon = 0.0;
   PisoActual = 0.0;
   LoteFijo = 0.0;
   DireccionEAPrincipal = -1;
   
   // 🆕 RESET DE VARIABLES DE TEMPORIZADOR
   InWaitingState = false;
   TimerStart = 0;
   
   BloqueoPorCierre = false; // 🆕 RESETEAR BLOQUEO
   UltimoCierreTendencia = 0; // 🆕 RESETEAR PERÍODO REFLEXIÓN
   
   GlobalVariableSet("Protector_EpisodioDireccion", -1);
   GlobalVariableSet("Protector_EpisodioLoteBase", 0.0);
   GlobalVariableSet("Protector_EpisodioUltimoEscalon", 0.0);
   GlobalVariableSet("Protector_EpisodioPisoActual", 0.0);  // 🆕 NUEVA LÍNEA
   GlobalVariableSet("Protector_EpisodioInicio", 0);
}

//+------------------------------------------------------------------+
//| Cargar datos persistentes (MEJORADA CON INICIALIZACIÓN ROBUSTA) |
//+------------------------------------------------------------------+
void LoadPersistentData()
{
   // Inicializar con valores por defecto ANTES de cargar desde global variables
   RecoveryCount = 0;
   MaxHistoricPositions = 0;
   MaxHistoricLoss = 0.0;
   MaxHistoricSpread = 0.0;
   MaxDrawdownHistoric = 0.0;
   BalanceAtMaxDrawdown = AccountBalance();
   LoteMaxAtMaxDrawdown = LoteMinimo;
   BloqueoPorCierre = false; // 🆕 INICIALIZAR BLOQUEO
   
   // Cargar RecoveryCount
   if(GlobalVariableCheck("Protector_RecoveryCount"))
      RecoveryCount = (int)GlobalVariableGet("Protector_RecoveryCount");
   
   // Cargar MaxHistoricPositions
   if(GlobalVariableCheck("Protector_MaxPositions"))
      MaxHistoricPositions = (int)GlobalVariableGet("Protector_MaxPositions");
   
   // Cargar MaxHistoricLoss
   if(GlobalVariableCheck("Protector_MaxLoss"))
      MaxHistoricLoss = GlobalVariableGet("Protector_MaxLoss");
   
   // Cargar MaxHistoricSpread
   if(GlobalVariableCheck("Protector_MaxSpread"))
      MaxHistoricSpread = GlobalVariableGet("Protector_MaxSpread");
      
   // MODIFICACIÓN 2: Cargar datos del peor escenario histórico
   if(GlobalVariableCheck("Protector_MaxDrawdownHistoric"))
      MaxDrawdownHistoric = GlobalVariableGet("Protector_MaxDrawdownHistoric");
   
   if(GlobalVariableCheck("Protector_BalanceAtMaxDrawdown"))
      BalanceAtMaxDrawdown = GlobalVariableGet("Protector_BalanceAtMaxDrawdown");
   
   if(GlobalVariableCheck("Protector_LoteMaxAtMaxDrawdown"))
      LoteMaxAtMaxDrawdown = GlobalVariableGet("Protector_LoteMaxAtMaxDrawdown");
      
   // Cargar datos del episodio si existe
   EpisodioDireccion = -1;
   EpisodioLoteBase = 0.0;
   EpisodioUltimoEscalon = 0.0;
   EpisodioPisoActual = 0.0;
   EpisodioInicio = 0;

   if(GlobalVariableCheck("Protector_EpisodioDireccion"))
      EpisodioDireccion = (int)GlobalVariableGet("Protector_EpisodioDireccion");
   
   if(GlobalVariableCheck("Protector_EpisodioLoteBase"))
      EpisodioLoteBase = GlobalVariableGet("Protector_EpisodioLoteBase");
   
   if(GlobalVariableCheck("Protector_EpisodioUltimoEscalon"))
      EpisodioUltimoEscalon = GlobalVariableGet("Protector_EpisodioUltimoEscalon");
      
   // 🆕 CARGAR PISO ACTUAL
   if(GlobalVariableCheck("Protector_EpisodioPisoActual"))
      EpisodioPisoActual = GlobalVariableGet("Protector_EpisodioPisoActual");
   
   if(GlobalVariableCheck("Protector_EpisodioInicio"))
      EpisodioInicio = (datetime)GlobalVariableGet("Protector_EpisodioInicio");
      
   // Restaurar modo protección si estaba activo
   if(EpisodioDireccion != -1 && EpisodioInicio > 0)
   {
      ModoProteccionActivado = true;
      DireccionEAPrincipal = EpisodioDireccion;
      LoteFijo = EpisodioLoteBase;
      UltimoEscalon = EpisodioUltimoEscalon;
      PisoActual = EpisodioPisoActual;  // 🆕 RESTAURAR PISO ACTUAL
      Print("Modo protección restaurado desde datos persistentes - Piso: " + DoubleToString(PisoActual, 2) + "%");
   }
}

//+------------------------------------------------------------------+
//| Guardar datos persistentes                                       |
//+------------------------------------------------------------------+
void SavePersistentData()
{
   GlobalVariableSet("Protector_RecoveryCount", RecoveryCount);
   GlobalVariableSet("Protector_MaxPositions", MaxHistoricPositions);
   GlobalVariableSet("Protector_MaxLoss", MaxHistoricLoss);
   GlobalVariableSet("Protector_MaxSpread", MaxHistoricSpread);
   
   // MODIFICACIÓN 2: Guardar datos del peor escenario histórico
   GlobalVariableSet("Protector_MaxDrawdownHistoric", MaxDrawdownHistoric);
   GlobalVariableSet("Protector_BalanceAtMaxDrawdown", BalanceAtMaxDrawdown);
   GlobalVariableSet("Protector_LoteMaxAtMaxDrawdown", LoteMaxAtMaxDrawdown);
   
   // Guardar datos del episodio si está activo
   if(ModoProteccionActivado)
   {
      GlobalVariableSet("Protector_EpisodioDireccion", EpisodioDireccion);
      GlobalVariableSet("Protector_EpisodioLoteBase", EpisodioLoteBase);
      GlobalVariableSet("Protector_EpisodioUltimoEscalon", EpisodioUltimoEscalon);
      GlobalVariableSet("Protector_EpisodioPisoActual", EpisodioPisoActual);
      GlobalVariableSet("Protector_EpisodioInicio", EpisodioInicio);
   }
}

//+------------------------------------------------------------------+
//| Normalizar símbolo para comparaciones robustas                  |
//+------------------------------------------------------------------+
string NormalizeSymbol(string symbol)
{
   if(symbol == "") return "";
   
   string normalized = symbol;
   int len = StringLen(normalized);
   
   // Convertir a mayúsculas
   for(int i = 0; i < len; i++)
   {
      int charCode = StringGetChar(normalized, i);
      if(charCode >= 97 && charCode <= 122) // 'a' to 'z' en ASCII
      {
         StringSetChar(normalized, i, (uchar)(charCode - 32)); // CONVERSIÓN EXPLÍCITA A uchar
      }
   }
   
   // Resto del código igual...
   return normalized;
}

//+------------------------------------------------------------------+
//| Obtener símbolo real para operaciones                           |
//+------------------------------------------------------------------+
string GetTradingSymbol()
{
   // Buscar el símbolo real usado en el mercado
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      string chartSymbol = ChartSymbol(chartId);
      if(NormalizeSymbol(chartSymbol) == SymbolXAU)
         return chartSymbol; // Devolver el símbolo exacto del gráfico
      chartId = ChartNext(chartId);
   }
   
   // Si no encuentra gráficos, probar variantes comunes
   string possibleSymbols[] = {"XAUUSD", "XAUUSD.", "GOLD", "XAUUSDm", "XAUUSDmicro"};
   for(int i = 0; i < ArraySize(possibleSymbols); i++)
   {
      if(SymbolSelect(possibleSymbols[i], true))
      {
         Print("Símbolo seleccionado: " + possibleSymbols[i]);
         return possibleSymbols[i];
      }
   }
   
   // Último recurso
   Print("Advertencia: Usando símbolo por defecto XAUUSD");
   return "XAUUSD";
}

//+------------------------------------------------------------------+
//| Detectar dirección del EA principal (SIMPLIFICADA)               |
//+------------------------------------------------------------------+
bool DetectarDireccionEAPrincipal()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            if(OrderType() == OP_BUY)
            {
               DireccionEAPrincipal = OP_BUY;
               return true;
            }
            else if(OrderType() == OP_SELL)
            {
               DireccionEAPrincipal = OP_SELL;
               return true;
            }
         }
      }
   }
   
   Print("Advertencia: No hay posiciones abiertas del EA principal");
   return false;
}

//+------------------------------------------------------------------+
//| Calcular lote híbrido adaptativo (CORREGIDA)                    |
//+------------------------------------------------------------------+
void CalcularLoteInicial()
{
   int totalPosiciones = CountOpenPositions();
   
   double lotePorPosiciones = totalPosiciones * FactorPosiciones;
   double equity = AccountEquity();
   double marginRequired = MarketInfo(TradingSymbol, MODE_MARGINREQUIRED);
   double lotePorEquity = LoteMinimo;
   
   if(marginRequired > 0.001)
      lotePorEquity = (equity * FactorEquity) / marginRequired;
   else
      Print("⚠️  Margen requerido es cero o muy bajo. Usando lote mínimo.");

   // 🆕 CÁLCULO DEL LOTE FINAL
   double loteCalculado = MathMax(lotePorPosiciones, lotePorEquity);
   loteCalculado = MathMin(loteCalculado, LoteMaximo);
   loteCalculado = MathMax(loteCalculado, LoteMinimo);
   
   LoteFijo = NormalizeDouble(loteCalculado, 2);
   
   Print(StringFormat("Lote calculado: %.3f (Pos: %.3f, Equity: %.3f)", 
                     LoteFijo, lotePorPosiciones, lotePorEquity));
}

//+------------------------------------------------------------------+
//| Ajustar lote por margen disponible                               |
//+------------------------------------------------------------------+
double AjustarLotePorMargen(double lote)
{
   double margenLibre = AccountFreeMargin();
   double margenRequerido = MarketInfo(TradingSymbol, MODE_MARGINREQUIRED);
   
   if(margenRequerido <= 0) return lote;
   
   double loteMaximoPorMargen = margenLibre / margenRequerido;
   double loteAjustado = MathMin(lote, loteMaximoPorMargen);
   
   // Asegurar lote mínimo
   loteAjustado = MathMax(loteAjustado, LoteMinimo);
   
   if(loteAjustado < lote)
   {
      Print(StringFormat("Lote ajustado por margen: %.3f -> %.3f", lote, loteAjustado));
   }
   
   return NormalizeDouble(loteAjustado, 2);
}

//+------------------------------------------------------------------+
//| Cerrar gráficos XAUUSD con reintentos robustos - VERSIÓN CORREGIDA |
//+------------------------------------------------------------------+
bool CerrarGraficoXAUUSDConReintentos()
{
   int totalGraficos = 0;
   int graficosCerrados = 0;
   
   // ✅ CONTADOR DE SEGURIDAD PARA EVITAR BUCLE INFINITO
   int maxCharts = 100; // Máximo razonable de gráficos
   int chartCount = 0;
   
   // PRIMERO: Contar gráficos XAUUSD
   long chartId = ChartFirst();
   while(chartId >= 0 && chartCount < maxCharts)
   {
      string chartSymbol = ChartSymbol(chartId);
      if(NormalizeSymbol(chartSymbol) == SymbolXAU)
         totalGraficos++;
      
      chartId = ChartNext(chartId);
      chartCount++;
   }
   
   if(totalGraficos == 0) 
   {
      Print("No hay gráficos XAUUSD abiertos");
      return true;
   }
   
   Print("Cerrando " + IntegerToString(totalGraficos) + " gráficos XAUUSD");
   
   // SEGUNDO: Cerrar gráficos con reintentos
   for(int intento = 0; intento < MaxReintentosCierre; intento++)
   {
      graficosCerrados = 0;
      chartCount = 0; // Reset contador de seguridad
      chartId = ChartFirst();
      
      while(chartId >= 0 && chartCount < maxCharts)
      {
         string chartSymbol = ChartSymbol(chartId);
         if(NormalizeSymbol(chartSymbol) == SymbolXAU)
         {
            if(ChartClose(chartId))
            {
               graficosCerrados++;
               Print("Gráfico cerrado exitosamente: " + chartSymbol);
            }
            else
            {
               Print("Fallo al cerrar gráfico: " + chartSymbol);
            }
         }
         
         // ✅ OBTENER SIGUIENTE GRÁFICO ANTES DE CONTINUAR
         long nextChartId = ChartNext(chartId);
         if(nextChartId == chartId) 
         {
            Print("⚠️  ChartNext() devolvió el mismo ID. Forzando avance...");
            break; // Romper bucle si no avanza
         }
         chartId = nextChartId;
         chartCount++;
      }
      
      if(graficosCerrados == totalGraficos)
      {
         Print("✅ Todos los gráficos cerrados en intento " + IntegerToString(intento+1));
         return true;
      }
      
      if(intento < MaxReintentosCierre - 1)
      {
         int pendientes = totalGraficos - graficosCerrados;
         Print("Reintento " + IntegerToString(intento+1) + ": " + IntegerToString(pendientes) + " gráficos pendientes");
         Sleep(1000 * (intento + 1)); // Backoff progresivo
      }
   }
   
   int pendientes = totalGraficos - graficosCerrados;
   Alert("❌ CRÍTICO: " + IntegerToString(pendientes) + " gráficos XAUUSD no se cerraron");
   return false;
}

//+------------------------------------------------------------------+
//| Abrir cobertura con reintentos robustos                         |
//+------------------------------------------------------------------+
bool AbrirCoberturaConReintentos()
{
   if(DireccionEAPrincipal != OP_BUY && DireccionEAPrincipal != OP_SELL)
      return false;
   
   int tipoOrden;
   double precio;
   
   if(DireccionEAPrincipal == OP_BUY)
   {
      tipoOrden = OP_SELL;
      precio = MarketInfo(TradingSymbol, MODE_BID);
   }
   else
   {
      tipoOrden = OP_BUY;
      precio = MarketInfo(TradingSymbol, MODE_ASK);
   }
   
   // Ajustar lote por margen en cada apertura
   double loteAjustado = AjustarLotePorMargen(LoteFijo);
   
   if(loteAjustado < LoteMinimo)
   {
      Print("Error: Lote ajustado es menor al mínimo permitido");
      return false;
   }
   
   int erroresRecuperables[] = {10004, 10006, 10007, 10008, 147};
   datetime tiempoInicio = TimeCurrent();
   int timeoutMaximo = 40;
   
   for(int intento = 0; intento < MaxReintentosOrden; intento++)
   {
      if(TimeCurrent() - tiempoInicio >= timeoutMaximo)
      {
         Print("TIMEOUT: No se pudo abrir cobertura después de " + IntegerToString(timeoutMaximo) + " segundos");
         return false;
      }
      
      GetLastError(); // 🆕 EVITA PROPAGACIÓN DE ERRORES
      int ticket = OrderSend(TradingSymbol, tipoOrden, loteAjustado, precio, 3, 0, 0, 
                            "Cobertura Protector", Magic_Number, 0, clrGreen);
      
      if(ticket > 0)
      {
         Print("Cobertura abierta exitosamente (ticket: " + IntegerToString(ticket) + ") después de " + IntegerToString(intento+1) + " intentos");
         return true;
      }
      else
      {
         int error = GetLastError();
         bool esRecuperable = false;
         
         for(int i = 0; i < ArraySize(erroresRecuperables); i++)
         {
            if(error == erroresRecuperables[i])
            {
               esRecuperable = true;
               break;
            }
         }
         
         if(!esRecuperable)
         {
            Print("Error FATAL abriendo cobertura: " + IntegerToString(error));
            return false;
         }
         
         int sleepTime = 200 * (intento + 1);
         Print("Reintento " + IntegerToString(intento+1) + " para abrir cobertura (error: " + IntegerToString(error) + "), esperando " + IntegerToString(sleepTime) + " ms");
         Sleep(sleepTime);
         
         if(DireccionEAPrincipal == OP_BUY)
            precio = MarketInfo(TradingSymbol, MODE_BID);
         else
            precio = MarketInfo(TradingSymbol, MODE_ASK);
      }
   }
   
   Print("FALLO PERSISTENTE: No se pudo abrir cobertura después de " + IntegerToString(MaxReintentosOrden) + " intentos");
   return false;
}

//+------------------------------------------------------------------+
//| Cerrar coberturas con reintentos robustos - SOLO POSICIONES GANADORAS |
//+------------------------------------------------------------------+
bool CerrarCoberturasConReintentos()
{
   int erroresRecuperables[] = {10004, 10006, 10007, 10008, 147};
   int coberturasCerradas = 0;
   int totalCoberturasGanadoras = 0;
   
   // Contar solo coberturas con ganancias
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU && 
            OrderMagicNumber() == Magic_Number)
         {
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            if(profit > 0)
            {
               totalCoberturasGanadoras++;
            }
         }
      }
   }
   
   if(totalCoberturasGanadoras == 0) 
   {
      Print("No hay coberturas con ganancias para cerrar");
      return true;
   }
   
   datetime tiempoInicio = TimeCurrent();
   int timeoutMaximo = 40;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU && 
            OrderMagicNumber() == Magic_Number)
         {
            // VERIFICAR SI TIENE GANANCIAS ANTES DE CERRAR
            double profit = OrderProfit() + OrderSwap() + OrderCommission();
            if(profit > 0) // SOLO CERRAR POSICIONES GANADORAS
            {
               double precioCierre;
               
               if(OrderType() == OP_BUY)
                  precioCierre = MarketInfo(TradingSymbol, MODE_BID);
               else
                  precioCierre = MarketInfo(TradingSymbol, MODE_ASK);
               
               bool cerrada = false;
               
               for(int intento = 0; intento < MaxReintentosOrden; intento++)
               {
                  if(TimeCurrent() - tiempoInicio >= timeoutMaximo)
                  {
                     Print("TIMEOUT en cierre de coberturas");
                     break;
                  }
                  
                  GetLastError(); // 🆕 EVITA PROPAGACIÓN DE ERRORES
                  if(OrderClose(OrderTicket(), OrderLots(), precioCierre, 3, clrNONE))
                  {
                     coberturasCerradas++;
                     cerrada = true;
                     
                     // Si se cierra por tendencia, activar período de reflexión
                     if(TendenciaH4Confirmada())
                     {
                        UltimoCierreTendencia = TimeCurrent();
                        Print("🕒 Período de reflexión de 12 horas iniciado");
                     }
                     
                     break;
                  }
                  else
                  {
                     int error = GetLastError();
                     bool esRecuperable = false;
                     
                     for(int j = 0; j < ArraySize(erroresRecuperables); j++)
                     {
                        if(error == erroresRecuperables[j])
                        {
                           esRecuperable = true;
                           break;
                        }
                     }
                     
                     if(!esRecuperable)
                     {
                        Print("Error FATAL cerrando orden " + IntegerToString(OrderTicket()) + ": " + IntegerToString(error));
                        break;
                     }
                     
                     int sleepTime = 100 * (intento + 1);
                     Print("Reintento " + IntegerToString(intento+1) + " para cerrar orden " + IntegerToString(OrderTicket()) + " (error: " + IntegerToString(error) + ")");
                     Sleep(sleepTime);
                     
                     if(OrderType() == OP_BUY)
                        precioCierre = MarketInfo(TradingSymbol, MODE_BID);
                     else
                        precioCierre = MarketInfo(TradingSymbol, MODE_ASK);
                  }
               }
               
               if(!cerrada)
               {
                  Print("No se pudo cerrar orden " + IntegerToString(OrderTicket()) + " después de " + IntegerToString(MaxReintentosOrden) + " intentos");
               }
            }
         }
      }
   }
   
   Print("Coberturas cerradas: " + IntegerToString(coberturasCerradas) + "/" + IntegerToString(totalCoberturasGanadoras));
   return (coberturasCerradas == totalCoberturasGanadoras);
}

//+------------------------------------------------------------------+
//| Desactivar modo protección                                       |
//+------------------------------------------------------------------+
void DesactivarModoProteccion()
{
   ModoProteccionActivado = false;
   GraficoCerrado = false;
   ResetearEpisodio();
   
   string mensaje = StringFormat("MODO PROTECCIÓN DESACTIVADO - Equity: $%.2f (%.1f%%)", 
                                AccountEquity(), (AccountEquity()/AccountBalance())*100);
   
   SendNotifications(mensaje);
   PlayAlarmSound();
   Print(mensaje);
}

//+------------------------------------------------------------------+
//| Obtener spread para XAUUSD específicamente en pips              |
//+------------------------------------------------------------------+
double GetSpreadForXAUUSD() 
{
    double bid = MarketInfo(TradingSymbol, MODE_BID);
    double ask = MarketInfo(TradingSymbol, MODE_ASK);
    double point = MarketInfo(TradingSymbol, MODE_POINT);
    
    // 🆕 PROTECCIÓN EXTRA
    if(bid == 0 || ask == 0 || point == 0) {
        Print("Error: Valores de mercado inválidos");
        return 0;
    }
    
    double spread = (ask - bid) / point;
    int digits = (int)MarketInfo(TradingSymbol, MODE_DIGITS);
    
    if(digits == 3 || digits == 5) {
        spread /= 10;
    }
    
    return spread;
}
//+------------------------------------------------------------------+
//| Eliminar panel visual DE TODOS LOS GRÁFICOS                     |
//+------------------------------------------------------------------+
void DeleteMonitoringPanel()
{
   string obj_names[] = {
      "PanelBG", "LblPositions", "LblLoss", "LblMaxLoss", 
      "LblRecoveries", "LblSpread", "LblMaxSpread", 
      "LblPeorEscenario", "LblEstado", "LblSpreadSet", 
      "LblMargen", "LblBalance"
   };
   
   // Eliminar objetos de TODOS los gráficos
   long chartId = ChartFirst();
   int chartCount = 0;
   
   while(chartId >= 0 && chartCount < 100) // Contador de seguridad
   {
      for(int i = 0; i < ArraySize(obj_names); i++)
      {
         ObjectDelete(chartId, obj_names[i]);
      }
      
      chartId = ChartNext(chartId);
      chartCount++;
   }
   
   // Eliminar también del gráfico actual (por si acaso)
   for(int i = 0; i < ArraySize(obj_names); i++)
   {
      ObjectDelete(0, obj_names[i]);
   }
}

//+------------------------------------------------------------------+
//| Crear panel de monitoreo visual (ACTUALIZADA)                   |
//+------------------------------------------------------------------+
void CreateMonitoringPanel()
{
   int x = 100;
   int y = 20;
   int spacing = 25;
   
   long chartId = ChartFirst();
   while(chartId >= 0) {
      // Fondo del panel
      ObjectCreate(chartId, "PanelBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XDISTANCE, x - 10);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YDISTANCE, y - 5);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XSIZE, 300);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YSIZE, 225);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_BGCOLOR, PANEL_BG);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_BACK, true);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_SELECTABLE, false);
      
      // Etiquetas - CON NOMBRES ÚNICOS
      CreateChartLabel(chartId, "LblPositions", "Posiciones: ", x, y, COLOR_POSITIONS);
      CreateChartLabel(chartId, "LblLoss", "Pérdida: ", x, y + spacing, COLOR_LOSS);
      CreateChartLabel(chartId, "LblMaxLoss", "Pérdida Máx: ", x, y + spacing*2, COLOR_MAX_VALUES);
      CreateChartLabel(chartId, "LblRecoveries", "Recuperaciones: ", x, y + spacing*3, COLOR_RECOVERY);
      CreateChartLabel(chartId, "LblSpread", "Spread Actual: ", x, y + spacing*4, COLOR_SPREAD);
      CreateChartLabel(chartId, "LblMaxSpread", "Spread Máx Hist: ", x, y + spacing*5, COLOR_MAX_VALUES);
      CreateChartLabel(chartId, "LblPeorEscenario", "Peor Escenario: ", x, y + spacing*6, COLOR_SPREAD);
      CreateChartLabel(chartId, "LblEstado", "Estado: ", x, y + spacing*7, COLOR_MARGEN);
      
      chartId = ChartNext(chartId);
   }
}

//+------------------------------------------------------------------+
//| Crear una etiqueta en un gráfico específico                      |
//+------------------------------------------------------------------+
void CreateChartLabel(long chartId, string name, string text, int x, int y, color clr)
{
   ObjectCreate(chartId, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chartId, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chartId, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(chartId, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chartId, name, OBJPROP_FONTSIZE, 18);
   ObjectSetInteger(chartId, name, OBJPROP_BACK, false);
   ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Actualizar el valor de una etiqueta en un gráfico específico     |
//+------------------------------------------------------------------+
void UpdateChartLabel(long chartId, string name, string text, color clr=CLR_NONE)
{
   if(ObjectFind(chartId, name) < 0) return;
   ObjectSetString(chartId, name, OBJPROP_TEXT, text);
   if(clr != CLR_NONE) 
      ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Actualizar paneles en todos los gráficos                         |
//+------------------------------------------------------------------+
void UpdateAllChartsPanels(double equityPercent, double spread)
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      UpdateMonitoringPanel(equityPercent, spread, chartId);
      chartId = ChartNext(chartId);
   }
}

//+------------------------------------------------------------------+
//| Actualizar panel de monitoreo con cambios visuales (MODIFICADA)  |
//+------------------------------------------------------------------+
void UpdateMonitoringPanel(double equityPercent, double spread, long chartId)
{
   double lossPercent = 100.0 - equityPercent;
   double diferenciaPercent = equityPercent - 100.0;
   
   // Cálculo de Pérdida/Ganancia
   string lossGainText;
   color lossGainColor;
   
   if(diferenciaPercent >= 0)
   {
      lossGainText = StringFormat("Ganancia: +%.2f%%", diferenciaPercent);
      lossGainColor = COLOR_POSITIONS;
   }
   else
   {
      lossGainText = StringFormat("Pérdida: %.2f%%", MathAbs(diferenciaPercent));
      lossGainColor = COLOR_LOSS;
   }
   
   // 🆕 ACTUALIZACIÓN CORREGIDA - USAR OBJETOS QUE SÍ EXISTEN
   UpdateChartLabel(chartId, "LblPositions", 
                   "Posiciones: " + IntegerToString(CurrentOpenPositions) + " | Máx: " + IntegerToString(MaxHistoricPositions));
   
   UpdateChartLabel(chartId, "LblLoss", lossGainText, lossGainColor);
   
   string maxLossText = "Pérdida Máx Hist: " + DoubleToString(MaxHistoricLoss, 2) + "%";
   UpdateChartLabel(chartId, "LblMaxLoss", maxLossText);
   
   UpdateChartLabel(chartId, "LblSpread", "Spread Actual: " + DoubleToString(spread, 1) + " pips");
   UpdateChartLabel(chartId, "LblMaxSpread", "Spread Máx Hist: " + DoubleToString(MaxHistoricSpread, 1) + " pips");
   
   UpdateChartLabel(chartId, "LblRecoveries", "Recuperaciones: " + IntegerToString(RecoveryCount));

   // 🆕 INFORMACIÓN DEL PEOR ESCENARIO - CORREGIDO
   string peorEscenarioText = StringFormat("Peor Escenario: %.1f%% drawdown", MaxDrawdownHistoric);
   UpdateChartLabel(chartId, "LblPeorEscenario", peorEscenarioText, COLOR_SPREAD);
   
   // 🆕 ESTADO DEL PROTECTOR - CORREGIDO
   string estadoText;
   color estadoColor;
   
   if(ModoProteccionActivado)
   {
      estadoText = "🔴 MODO PROTECCIÓN ACTIVO";
      estadoColor = clrRed;
   }
   else if(InWaitingState)
   {
      int segundosRestantes = MinDuration * 60 - (int)(TimeCurrent() - TimerStart);
      estadoText = "🟡 TEMPORIZADOR: " + IntegerToString(segundosRestantes) + "s";
      estadoColor = clrYellow;
   }
   else
   {
      estadoText = "🟢 MODO VIGILANCIA";
      estadoColor = clrGreen;
   }
   
   UpdateChartLabel(chartId, "LblEstado", estadoText, estadoColor);
}

//+------------------------------------------------------------------+
//| Contar posiciones abiertas                                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Reproducir sonido de alarma (VERSIÓN ÚNICA CORREGIDA)           |
//+------------------------------------------------------------------+
void PlayAlarmSound()
{
   if(!Habilitar_Alertas_Sonido) return;
   
   // ✅ VERIFICACIÓN MÁS ROBUSTA
   if(FileIsExist(SoundFile, 0)) {
      PlaySound(SoundFile);
   } else {
      // Intentar en directorio de sonidos
      string soundPath = "sounds\\" + SoundFile;
      if(FileIsExist(soundPath, 0)) {
         PlaySound(soundPath);
      } else {
         PlaySound("alert.wav"); // Sonido por defecto
      }
   }
}

//+------------------------------------------------------------------+
//| Enviar notificaciones (VERSIÓN ÚNICA CORREGIDA)                 |
//+------------------------------------------------------------------+
void SendNotifications(string message)
{
   if(Habilitar_Notificaciones)
   {
      SendMail("Alerta Protector20", message);
      SendNotification(message);
   }
   else
   {
      Print("NOTIFICACIÓN: " + message); // Solo en log
   }
}

//+------------------------------------------------------------------+
//| Actualizar máximos históricos (MODIFICADA CON INDICADOR HISTÓRICO) |
//+------------------------------------------------------------------+
void UpdateHistoricalTrackers(double equityPercent, double spread)
{
   double lossPercent = 100.0 - equityPercent;
   
   if(CurrentOpenPositions > MaxHistoricPositions)
   {
      MaxHistoricPositions = CurrentOpenPositions;
   }
   
   if(lossPercent > MaxHistoricLoss)
   {
      MaxHistoricLoss = lossPercent;
   }
   
   if(spread > MaxHistoricSpread)
   {
      MaxHistoricSpread = spread;
   }
   
   // MODIFICACIÓN 2: Calcular peor escenario histórico
   double drawdownActual = 100.0 - equityPercent;

   if(drawdownActual > MaxDrawdownHistoric)
   {
      MaxDrawdownHistoric = drawdownActual;
      BalanceAtMaxDrawdown = AccountBalance();
      
      // Calcular lote máximo en peor escenario
      double marginRequired = MarketInfo(TradingSymbol, MODE_MARGINREQUIRED);
      if(marginRequired > 0)
      {
         LoteMaxAtMaxDrawdown = (BalanceAtMaxDrawdown * MaxDrawdownHistoric / 100.0) / marginRequired;
         LoteMaxAtMaxDrawdown = MathMin(LoteMaxAtMaxDrawdown, LoteMaximo);
         LoteMaxAtMaxDrawdown = MathMax(LoteMaxAtMaxDrawdown, LoteMinimo);
         LoteMaxAtMaxDrawdown = NormalizeDouble(LoteMaxAtMaxDrawdown, 2);
      }
      
      Print(StringFormat("NUEVO PEOR ESCENARIO: Drawdown %.1f%%, Balance: $%.0f, Lote Máx: %.2f", 
                        MaxDrawdownHistoric, BalanceAtMaxDrawdown, LoteMaxAtMaxDrawdown));
   }
}

//+------------------------------------------------------------------+
//| Tendencia H4 confirmada (5 filtros)                             |
//+------------------------------------------------------------------+
bool TendenciaH4Confirmada()
{
   // Respetar período de reflexión post-cierre
   if(UltimoCierreTendencia > 0) {
      double horasDesdeCierre = (TimeCurrent() - UltimoCierreTendencia) / 3600.0;
      if(horasDesdeCierre < PeriodoReflexionHoras) {
         Print("⏳ Período de reflexión activo. Faltan " + DoubleToString(PeriodoReflexionHoras - horasDesdeCierre, 1) + " horas");
         return false;
      }
   }

   // Determinar el tipo de cobertura abierta
   int tipoCobertura = -1;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU && OrderMagicNumber() == Magic_Number) {
            tipoCobertura = OrderType();
            break;
         }
      }
   }
   
   // Si no hay coberturas, no cerrar
   if(tipoCobertura == -1) return false;
   
   // Obtener valores de indicadores - FORMA CORRECTA MQL4
   double ema50 = iMA(TradingSymbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema200 = iMA(TradingSymbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE, 0);
   
   double macdMain = iMACD(TradingSymbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
   double macdSignal = iMACD(TradingSymbol, PERIOD_H4, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
   
   double rsi = iRSI(TradingSymbol, PERIOD_H4, 14, PRICE_CLOSE, 0);
   double adx = iADX(TradingSymbol, PERIOD_H4, 20, PRICE_CLOSE, MODE_MAIN, 0);
   
   // Calcular volumen promedio (20 periodos) - CORREGIDO
   double volumenPromedio = 0;
   for(int i = 0; i < 20; i++) {
      volumenPromedio += (double)iVolume(TradingSymbol, PERIOD_H4, i); // ✅ CAST EXPLÍCITO
   }
   volumenPromedio /= 20.0;
   double volumenActual = (double)iVolume(TradingSymbol, PERIOD_H4, 0); // ✅ CAST EXPLÍCITO
   
   // Contar condiciones cumplidas
   bool condicionEMA = false;
   bool condicionMACD = false;
   bool condicionADX = false;
   bool condicionRSI = false;
   bool condicionVolumen = false;
   
   // Filtro 1: EMA50 vs EMA200
   if(tipoCobertura == OP_SELL) {
      // Para coberturas SELL, cerrar si tendencia bajista (EMA50 < EMA200)
      condicionEMA = (ema50 < ema200);
   } else if(tipoCobertura == OP_BUY) {
      // Para coberturas BUY, cerrar si tendencia alcista (EMA50 > EMA200)
      condicionEMA = (ema50 > ema200);
   }
   
   // Filtro 2: MACD
   if(tipoCobertura == OP_SELL) {
      // Para coberturas SELL, cerrar si MACD < señal
      condicionMACD = (macdMain < macdSignal);
   } else if(tipoCobertura == OP_BUY) {
      // Para coberturas BUY, cerrar si MACD > señal
      condicionMACD = (macdMain > macdSignal);
   }
   
   // Filtro 3: ADX > 25 (fuerza de tendencia)
   condicionADX = (adx > 25);
   
   // Filtro 4: RSI
   if(tipoCobertura == OP_SELL) {
      // Para coberturas SELL, cerrar si RSI < 45 (sobreventa)
      condicionRSI = (rsi < 45);
   } else if(tipoCobertura == OP_BUY) {
      // Para coberturas BUY, cerrar si RSI > 55 (sobrecompra)
      condicionRSI = (rsi > 55);
   }
   
   // Filtro 5: Volumen > promedio
   condicionVolumen = (volumenActual > volumenPromedio);
   
   // Requerir 3 filtros estructurales (EMA, MACD, ADX) y al menos 1 contextual (RSI o Volumen)
   bool estructurales = condicionEMA && condicionMACD && condicionADX;
   bool contextuales = condicionRSI || condicionVolumen;
   
   bool tendenciaConfirmada = estructurales && contextuales;
   
   // Log detallado
   string tipoSeñal = (tipoCobertura == OP_SELL) ? "BAJISTA" : "ALCISTA";
   LogSeñalTendencia(tipoSeñal, condicionEMA, condicionMACD, condicionADX, condicionRSI, condicionVolumen, tendenciaConfirmada);
   
   return tendenciaConfirmada;
}

//+------------------------------------------------------------------+
//| Log detallado de señales                                         |
//+------------------------------------------------------------------+
void LogSeñalTendencia(string tipoSeñal, bool condicionEMA, bool condicionMACD, bool condicionADX, bool condicionRSI, bool condicionVolumen, bool decision)
{
   string mensaje = StringFormat("[%s] SEÑAL %s - ", TimeToString(TimeCurrent()), tipoSeñal);
   mensaje += StringFormat("EMA: %s, MACD: %s, ADX: %s, RSI: %s, Vol: %s | ",
                           condicionEMA ? "✅" : "❌",
                           condicionMACD ? "✅" : "❌", 
                           condicionADX ? "✅" : "❌",
                           condicionRSI ? "✅" : "❌",
                           condicionVolumen ? "✅" : "❌");
   mensaje += StringFormat("DECISIÓN: %s", decision ? "CERRAR" : "MANTENER");
   
   Print(mensaje);
   
   // Guardar en archivo si está habilitado
   if(GlobalVariableGet("Protector_Logging") == 1) {
      int handle = FileOpen("Protector20_Log.txt", FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(handle != INVALID_HANDLE) {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, mensaje);
         FileClose(handle);
      }
   }
}

//+------------------------------------------------------------------+
//| Generar reporte de backtesting                                   |
//+------------------------------------------------------------------+
void GenerarReporteBacktesting()
{
   if(!Modo_Backtest) return;
   
   string reporte = "\n=========================================\n";
   reporte += "REPORTE BACKTESTING - PROTECTOR20\n";
   reporte += "=========================================\n";
   reporte += StringFormat("Período: %s a %s\n", 
                           TimeToString(Fecha_Inicio_Backtest), 
                           TimeToString(Fecha_Fin_Backtest));
   reporte += "-----------------------------------------\n";
   reporte += StringFormat("Señales generadas: %d\n", Backtest_Señales_Generadas);
   reporte += StringFormat("Señales accionadas: %d\n", Backtest_Señales_Accionadas);
   reporte += StringFormat("Coberturas abiertas: %d\n", Backtest_Coberturas_Abiertas);
   reporte += StringFormat("Coberturas cerradas: %d\n", Backtest_Coberturas_Cerradas);
   reporte += StringFormat("Ganancia neta: $%.2f\n", Backtest_Ganancia_Neta);
   reporte += StringFormat("Drawdown máximo: %.2f%%\n", Backtest_Max_Drawdown);
   reporte += "=========================================\n";
   
   Print(reporte);
   
   // Guardar en archivo
   int handle = FileOpen("Protector20_Backtest_Report.txt", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE) {
      FileWrite(handle, reporte);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| MODIFICACIÓN 3: Tendencia bajista confirmada para cierre SELL   |
//+------------------------------------------------------------------+
bool TendenciaBajistaConfirmada()
{
    // Obtener indicadores en M1
    double ema5 = iMA(TradingSymbol, PERIOD_M1, 5, 0, MODE_EMA, PRICE_CLOSE, 0);
    double ema15 = iMA(TradingSymbol, PERIOD_M1, 15, 0, MODE_EMA, PRICE_CLOSE, 0);
    double bollingerLower = iBands(TradingSymbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, MODE_LOWER, 0);
    double rsi6 = iRSI(TradingSymbol, PERIOD_M1, 6, PRICE_CLOSE, 0);
    double volumenActual = (double)iVolume(TradingSymbol, PERIOD_M1, 0); // ✅ CAST EXPLÍCITO
    
    // Calcular volumen promedio manualmente
    double volumenPromedio = 0;
    for(int i = 0; i < 10; i++) {
        volumenPromedio += (double)iVolume(TradingSymbol, PERIOD_M1, i); // ✅ CAST EXPLÍCITO
    }
    volumenPromedio /= 10.0;
    
    // Condición: Tendencia bajista confirmada
    if(ema5 < ema15 && 
       Bid < bollingerLower && 
       rsi6 < 30 && 
       volumenActual > volumenPromedio)
    {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| MODIFICACIÓN 4: Tendencia alcista confirmada para cierre BUY    |
//+------------------------------------------------------------------+
bool TendenciaAlcistaConfirmada()
{
    // Obtener indicadores en M1
    double ema5 = iMA(TradingSymbol, PERIOD_M1, 5, 0, MODE_EMA, PRICE_CLOSE, 0);
    double ema15 = iMA(TradingSymbol, PERIOD_M1, 15, 0, MODE_EMA, PRICE_CLOSE, 0);
    double bollingerUpper = iBands(TradingSymbol, PERIOD_M1, 20, 2.0, 0, PRICE_CLOSE, MODE_UPPER, 0);
    double rsi6 = iRSI(TradingSymbol, PERIOD_M1, 6, PRICE_CLOSE, 0);
    double volumenActual = (double)iVolume(TradingSymbol, PERIOD_M1, 0); // ✅ CAST EXPLÍCITO
    
    // Calcular volumen promedio manualmente
    double volumenPromedio = 0;
    for(int i = 0; i < 10; i++) {
        volumenPromedio += (double)iVolume(TradingSymbol, PERIOD_M1, i); // ✅ CAST EXPLÍCITO
    }
    volumenPromedio /= 10.0;
    
    // Condición: Tendencia alcista confirmada
    if(ema5 > ema15 && 
       Ask > bollingerUpper && 
       rsi6 > 70 && 
       volumenActual > volumenPromedio)
    {
        return true;
    }
    
    return false;
}
//+------------------------------------------------------------------+