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

// --- NUEVAS VARIABLES PARA LÓGICA DE SERIES Y CONTEO ---
int            ConteoOrdenesSerie = 0;          // Rastrea el paso de la serie (A, B, C)
const int      MAX_POSICIONES_TOTAL = 11;       // Hard Cap de posiciones (Solo Paragua)
int            CurrentPrincipalPositions = 0;   // Para el monitor visual

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

// Variables de detección única
bool           DireccionDetectada = false;
datetime       TiempoDeteccion = 0;

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
}

void OnTimer()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   
   // Actualizar conteos para lógica y visualización
   CurrentOpenPositions = CountParaguaPositions();       // Para lógica interna
   CurrentPrincipalPositions = CountPrincipalPositions(); // Para visualización
   
   // Verificación de recalibración por distancia ≥10% (Trailing Floor)
   if(ModoProteccionActivado && (equityPercent - UltimoEscalon) >= 10.0)
   {
      PisoActual = equityPercent;
      UltimoEscalon = equityPercent;
      
      // ✅ RESET DINÁMICO DE SERIES
      // El piso subió, reiniciamos la secuencia a Serie A (pero NO el inventario)
      ConteoOrdenesSerie = 0; 
      
      Print("🔄 RECALIBRACIÓN COMPLETA - Piso subió. Serie reseteada a 0.");
   }
   
   MonitoreoPrincipal(equityPercent, spread);
   VerificarRecuperacionEquity(equityPercent);
   UpdateAllChartsPanels(equityPercent, spread);
   GestionarResetDeteccion();
}

void OnTick()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   
   // Actualizar conteos
   CurrentOpenPositions = CountParaguaPositions();
   CurrentPrincipalPositions = CountPrincipalPositions();
   
   if(ModoProteccionActivado && (equityPercent - UltimoEscalon) >= 10.0)
   {
      PisoActual = equityPercent;
      UltimoEscalon = equityPercent;
      
      // ✅ RESET DINÁMICO DE SERIES
      ConteoOrdenesSerie = 0;
      
      Print("🔄 RECALIBRACIÓN COMPLETA - Piso subió. Serie reseteada a 0.");
   }
   
   MonitoreoPrincipal(equityPercent, spread);
   VerificarRecuperacionEquity(equityPercent);
   UpdateAllChartsPanels(equityPercent, spread);
   GestionarResetDeteccion();
}

//+------------------------------------------------------------------+
//| Verificación continua de recuperación de equity                 |
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

void CheckActivationConditions(double equityPercent)
{
   // ✅ NO ACTIVAR SI YA ESTAMOS EN PROTECCIÓN
   if(ModoProteccionActivado)
      return;
   
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

void ActivarModoProteccion()
{
   if(ModoProteccionActivado) return;

   if(!DireccionDetectada)
   {
      if(!DetectarDireccionEAPrincipal()) return;
   }
   
   if(IsXAUUSDChartOpen())
   {
      if(!CerrarGraficoXAUUSDConReintentos()) return;
   }
   
   CalcularLoteInicial();
   
   double equity = AccountEquity();
   double balance = AccountBalance();
   PisoActual = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   UltimoEscalon = PisoActual;
   
   GuardarEpisodio();
   
   if(!AbrirCoberturaConReintentos()) return;
   
   ModoProteccionActivado = true;
   InWaitingState = false;
   TimerStart = 0;
   GraficoCerrado = true;
   
   // ✅ INICIALIZAR CONTADOR DE SERIE
   ConteoOrdenesSerie = 1; 
   
   string direccion = (DireccionEAPrincipal == OP_BUY) ? "BUY" : "SELL";
   string mensaje = StringFormat("MODO PROTECCIÓN ACTIVADO - Dir: %s - Lote: %.3f - Piso: %.2f%%", 
                                direccion, LoteFijo, PisoActual);
   SendNotifications(mensaje);
   PlayAlarmSound();
   Print(mensaje);
}

//+------------------------------------------------------------------+
//| Contar posiciones EXCLUSIVAS del Paragua (Magic Number 3030)     |
//+------------------------------------------------------------------+
int CountParaguaPositions()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            if(OrderMagicNumber() == Magic_Number) // Solo las mías
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Contar posiciones del EA PRINCIPAL (Todo MENOS Magic 3030)       |
//+------------------------------------------------------------------+
int CountPrincipalPositions()
{
   int count = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            // Ignorar mis propias órdenes de cobertura
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            count++; // Contar todo lo demás (EA Principal)
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calcular distancia requerida según la serie actual               |
//+------------------------------------------------------------------+
double ObtenerDistanciaProximoEscalon()
{
   // SERIE A (Posiciones 1, 2, 3) -> Distancia 1.0%
   if(ConteoOrdenesSerie < 3) return 1.0;
   
   // PAUSA 1 (Salto a Serie B - Posición 4) -> Distancia 5.0%
   if(ConteoOrdenesSerie == 3) return 5.0;
   
   // SERIE B (Posiciones 4, 5, 6) -> Distancia 1.0%
   if(ConteoOrdenesSerie < 6) return 1.0;
   
   // PAUSA 2 (Salto a Serie C - Posición 7) -> Distancia 10.0%
   if(ConteoOrdenesSerie == 6) return 10.0;
   
   // SERIE C (Posiciones 7 a 11) -> Distancia 1.0%
   return 1.0;
}

//+------------------------------------------------------------------+
//| Gestionar modo protección (MODIFICADA: SERIES + HARD CAP)        |
//+------------------------------------------------------------------+
void ManageProtectionMode(double equityPercent)
{
   // 1. HARD CAP (Límite Global de Inventario)
   // Cuenta SOLO posiciones del Paragua. Si hay 11, se bloquea.
   if(CountParaguaPositions() >= MAX_POSICIONES_TOTAL)
   {
      return;
   }

   // 2. Obtener distancia requerida según el paso de la serie
   double distanciaRequerida = ObtenerDistanciaProximoEscalon();
   
   // 3. Verificar si el precio cayó la distancia requerida
   if(equityPercent <= UltimoEscalon - distanciaRequerida)
   {
      if(AbrirCoberturaConReintentos())
      {
         // Actualizar escalón y contador de serie
         UltimoEscalon = UltimoEscalon - distanciaRequerida;
         ConteoOrdenesSerie++; // Avanzamos un paso en la secuencia
         
         Print(StringFormat("Nueva cobertura (Paso Serie: %d) - Distancia: %.1f%% - Nuevo Escalón: %.2f%%", 
                           ConteoOrdenesSerie, distanciaRequerida, UltimoEscalon));
      }
   }
}

//+------------------------------------------------------------------+
//| Activar plan B (VERSIÓN LIMPIA)                                 |
//+------------------------------------------------------------------+
void ActivarPlanB()
{
   string mensaje = "PLAN B ACTIVADO - Fallo crítico en el sistema";
   SendNotifications(mensaje);
   Alert(mensaje);
   
   // Desactivar modo protección COMPLETAMENTE
   ModoProteccionActivado = false;
   InWaitingState = false;
   TimerStart = 0;
   GraficoCerrado = false;
   
   // Resetear episodio
   ResetearEpisodio();
   
   Print("MODO PROTECCIÓN DESACTIVADO POR FALLO CRÍTICO - Intervención manual requerida");
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
   EpisodioPisoActual = 0.0;
   EpisodioInicio = 0;
   
   UltimoEscalon = 0.0;
   PisoActual = 0.0;
   LoteFijo = 0.0;
   DireccionEAPrincipal = -1;
   
   InWaitingState = false;
   TimerStart = 0;
   
   // ✅ RESET DE VARIABLES DE SERIE
   ConteoOrdenesSerie = 0;
   
   GlobalVariableSet("Protector_EpisodioDireccion", -1);
   GlobalVariableSet("Protector_EpisodioLoteBase", 0.0);
   GlobalVariableSet("Protector_EpisodioUltimoEscalon", 0.0);
   GlobalVariableSet("Protector_EpisodioPisoActual", 0.0);
   GlobalVariableSet("Protector_EpisodioInicio", 0);
   GlobalVariableSet("Protector_ConteoSerie", 0.0); 
   
   Print("🔄 Episodio de protección COMPLETAMENTE reseteado");
}

//+------------------------------------------------------------------+
//| Cargar datos persistentes (COMPLETA Y ACTUALIZADA)               |
//+------------------------------------------------------------------+
void LoadPersistentData()
{
   // 1. Inicializar con valores por defecto (Reseteo preventivo)
   RecoveryCount = 0;
   MaxHistoricPositions = 0;
   MaxHistoricLoss = 0.0;
   MaxHistoricSpread = 0.0;
   MaxDrawdownHistoric = 0.0;
   BalanceAtMaxDrawdown = AccountBalance();
   LoteMaxAtMaxDrawdown = LoteMinimo;
   
   // Variables de episodio
   EpisodioDireccion = -1;
   EpisodioLoteBase = 0.0;
   EpisodioUltimoEscalon = 0.0;
   EpisodioPisoActual = 0.0;
   EpisodioInicio = 0;
   
   // ✅ NUEVO: Inicializar contador de serie
   ConteoOrdenesSerie = 0; 

   // 2. Cargar Estadísticas Históricas y Contadores
   if(GlobalVariableCheck("Protector_RecoveryCount")) 
      RecoveryCount = (int)GlobalVariableGet("Protector_RecoveryCount");
      
   if(GlobalVariableCheck("Protector_MaxPositions")) 
      MaxHistoricPositions = (int)GlobalVariableGet("Protector_MaxPositions");
      
   if(GlobalVariableCheck("Protector_MaxLoss")) 
      MaxHistoricLoss = GlobalVariableGet("Protector_MaxLoss");
      
   if(GlobalVariableCheck("Protector_MaxSpread")) 
      MaxHistoricSpread = GlobalVariableGet("Protector_MaxSpread");
   
   // Cargar Peor Escenario Histórico
   if(GlobalVariableCheck("Protector_MaxDrawdownHistoric")) 
      MaxDrawdownHistoric = GlobalVariableGet("Protector_MaxDrawdownHistoric");
      
   if(GlobalVariableCheck("Protector_BalanceAtMaxDrawdown")) 
      BalanceAtMaxDrawdown = GlobalVariableGet("Protector_BalanceAtMaxDrawdown");
   
   if(GlobalVariableCheck("Protector_LoteMaxAtMaxDrawdown")) 
      LoteMaxAtMaxDrawdown = GlobalVariableGet("Protector_LoteMaxAtMaxDrawdown");

   // 3. Cargar Datos del Episodio de Protección (Si estaba activo)
   if(GlobalVariableCheck("Protector_EpisodioDireccion")) 
      EpisodioDireccion = (int)GlobalVariableGet("Protector_EpisodioDireccion");
      
   if(GlobalVariableCheck("Protector_EpisodioLoteBase")) 
      EpisodioLoteBase = GlobalVariableGet("Protector_EpisodioLoteBase");
   
   if(GlobalVariableCheck("Protector_EpisodioUltimoEscalon")) 
      EpisodioUltimoEscalon = GlobalVariableGet("Protector_EpisodioUltimoEscalon");
      
   if(GlobalVariableCheck("Protector_EpisodioPisoActual")) 
      EpisodioPisoActual = GlobalVariableGet("Protector_EpisodioPisoActual");
      
   if(GlobalVariableCheck("Protector_EpisodioInicio")) 
      EpisodioInicio = (datetime)GlobalVariableGet("Protector_EpisodioInicio");
   
   // ✅ NUEVO: Cargar el paso de la serie (A, B o C)
   if(GlobalVariableCheck("Protector_ConteoSerie"))
      ConteoOrdenesSerie = (int)GlobalVariableGet("Protector_ConteoSerie");
      
   // 4. Cargar Datos de Detección de Dirección del EA Principal
   if(GlobalVariableCheck("Protector_DireccionDetectada")) 
      DireccionDetectada = (bool)GlobalVariableGet("Protector_DireccionDetectada");
      
   if(GlobalVariableCheck("Protector_TiempoDeteccion")) 
      TiempoDeteccion = (datetime)GlobalVariableGet("Protector_TiempoDeteccion");
      
   // 5. Restaurar Estado del Sistema
   // Si hay un episodio guardado válido, reactivamos el modo protección
   if(EpisodioDireccion != -1 && EpisodioInicio > 0)
   {
      ModoProteccionActivado = true;
      DireccionEAPrincipal = EpisodioDireccion;
      LoteFijo = EpisodioLoteBase;
      UltimoEscalon = EpisodioUltimoEscalon;
      PisoActual = EpisodioPisoActual;
      
      Print("🔄 SISTEMA RESTAURADO: Modo Protección Activo");
      Print(StringFormat("   - Dirección: %s", (DireccionEAPrincipal==OP_BUY ? "BUY":"SELL")));
      Print(StringFormat("   - Piso: %.2f%%", PisoActual));
      Print(StringFormat("   - Paso Serie: %d", ConteoOrdenesSerie));
   }
   
   // 6. Verificación de Integridad
   // Si hay discrepancia entre la dirección detectada y la del episodio, manda la del episodio
   if(ModoProteccionActivado && DireccionDetectada)
   {
      if(DireccionEAPrincipal != EpisodioDireccion)
      {
         Print("⚠️ Corrigiendo inconsistencia en datos persistentes (Prioridad Episodio)");
         DireccionEAPrincipal = EpisodioDireccion;
      }
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
   GlobalVariableSet("Protector_MaxDrawdownHistoric", MaxDrawdownHistoric);
   GlobalVariableSet("Protector_BalanceAtMaxDrawdown", BalanceAtMaxDrawdown);
   GlobalVariableSet("Protector_LoteMaxAtMaxDrawdown", LoteMaxAtMaxDrawdown);

   if(ModoProteccionActivado)
   {
      GlobalVariableSet("Protector_EpisodioDireccion", EpisodioDireccion);
      GlobalVariableSet("Protector_EpisodioLoteBase", EpisodioLoteBase);
      GlobalVariableSet("Protector_EpisodioUltimoEscalon", EpisodioUltimoEscalon);
      GlobalVariableSet("Protector_EpisodioPisoActual", EpisodioPisoActual);
      GlobalVariableSet("Protector_EpisodioInicio", EpisodioInicio);
      
      // ✅ GUARDAR CONTEO DE SERIE
      GlobalVariableSet("Protector_ConteoSerie", ConteoOrdenesSerie);
   }
   
   GlobalVariableSet("Protector_DireccionDetectada", DireccionDetectada);
   GlobalVariableSet("Protector_TiempoDeteccion", TiempoDeteccion);
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

bool DetectarDireccionEAPrincipal()
{
   // ✅ SI YA SE DETECTÓ, NO VOLVER A DETECTAR
   if(DireccionDetectada)
   {
      Print("🔒 Dirección ya detectada - No redetectar");
      return (DireccionEAPrincipal == OP_BUY || DireccionEAPrincipal == OP_SELL);
   }

   int buysPrincipal = 0;
   int sellsPrincipal = 0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            // ✅ EXCLUIR ÓRDENES DEL PARAGUAS
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            if(OrderType() == OP_BUY) 
               buysPrincipal++;
            else if(OrderType() == OP_SELL) 
               sellsPrincipal++;
         }
      }
   }
   
   // ✅ LÓGICA DE DECISIÓN
   if(buysPrincipal > 0 && sellsPrincipal == 0)
   {
      DireccionEAPrincipal = OP_BUY;
      DireccionDetectada = true;
      TiempoDeteccion = TimeCurrent();
      Print("✅ Dirección detectada: BUY (" + IntegerToString(buysPrincipal) + " posiciones) - " + TimeToString(TiempoDeteccion));
      return true;
   }
   else if(sellsPrincipal > 0 && buysPrincipal == 0)
   {
      DireccionEAPrincipal = OP_SELL;
      DireccionDetectada = true;
      TiempoDeteccion = TimeCurrent();
      Print("✅ Dirección detectada: SELL (" + IntegerToString(sellsPrincipal) + " posiciones) - " + TimeToString(TiempoDeteccion));
      return true;
   }
   else if(buysPrincipal > 0 && sellsPrincipal > 0)
   {
      Print("🚨 ERROR: EA principal tiene operaciones mezcladas");
      return false;
   }
   else
   {
      Print("⚠️  No se detectaron operaciones del EA principal");
      return false;
   }
}

bool DebeResetearDeteccion()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            // Excluir órdenes del paraguas
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            // Si encuentra alguna orden del EA principal, NO resetear
            return false;
         }
      }
   }
   // No se encontraron órdenes del EA principal → SÍ resetear
   return true;
}

void GestionarResetDeteccion()
{
   if(DireccionDetectada && DebeResetearDeteccion())
   {
      DireccionDetectada = false;
      DireccionEAPrincipal = -1;
      Print("🔄 Reset detección - EA principal sin posiciones");
   }
}

// Llamar esta función en OnTick() y OnTimer()

//+------------------------------------------------------------------+
//| Calcular lote simplificado (Solo Posiciones)                     |
//+------------------------------------------------------------------+
void CalcularLoteInicial()
{   
   // 1. Obtener el conteo de posiciones del EA principal
   int totalPosiciones = CountPrincipalPositions();
   
   // 2. Calcular el lote basado en el factor de posiciones
   // FactorPosiciones es el multiplicador por posición (input double FactorPosiciones = 0.001;)
   double loteCalculado = totalPosiciones * FactorPosiciones;

   // 3. Aplicar límites (Máximo y Mínimo)
   // LoteMaximo y LoteMinimo son parámetros de entrada
   loteCalculado = MathMin(loteCalculado, LoteMaximo);
   loteCalculado = MathMax(loteCalculado, LoteMinimo);
   
   // 4. Asignar el lote fijo (asegurar 2 decimales para la mayoría de los brokers)
   LoteFijo = NormalizeDouble(loteCalculado, 2);
   
   Print(StringFormat("Lote fijo calculado (Solo Posiciones): %.3f (Total Posiciones Principal: %d)", 
                     LoteFijo, totalPosiciones));
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
//| Desactivar modo protección                                       |
//+------------------------------------------------------------------+
void DesactivarModoProteccion()
{
   ModoProteccionActivado = false;
   GraficoCerrado = false;
   
   // Resetear variables del episodio, pero NO la detección de dirección
   EpisodioLoteBase = 0.0;
   EpisodioUltimoEscalon = 0.0;
   EpisodioPisoActual = 0.0;
   EpisodioInicio = 0;
   
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
   double diferenciaPercent = equityPercent - 100.0;
   string lossGainText;
   color lossGainColor;
   if(diferenciaPercent >= 0) {
      lossGainText = StringFormat("Ganancia: +%.2f%%", diferenciaPercent);
      lossGainColor = COLOR_POSITIONS;
   } else {
      lossGainText = StringFormat("Pérdida: %.2f%%", MathAbs(diferenciaPercent));
      lossGainColor = COLOR_LOSS;
   }
   
   // ✅ MODIFICADO: Muestra CurrentPrincipalPositions (EA Principal)
   UpdateChartLabel(chartId, "LblPositions", 
                   "Posiciones: " + IntegerToString(CurrentPrincipalPositions) + " | Máx: " + IntegerToString(MaxHistoricPositions));
                   
   UpdateChartLabel(chartId, "LblLoss", lossGainText, lossGainColor);
   UpdateChartLabel(chartId, "LblMaxLoss", "Pérdida Máx Hist: " + DoubleToString(MaxHistoricLoss, 2) + "%");
   UpdateChartLabel(chartId, "LblSpread", "Spread: " + DoubleToString(spread, 1));
   UpdateChartLabel(chartId, "LblMaxSpread", "Máx Spread: " + DoubleToString(MaxHistoricSpread, 1));
   UpdateChartLabel(chartId, "LblRecoveries", "Recuperaciones: " + IntegerToString(RecoveryCount));
   UpdateChartLabel(chartId, "LblPeorEscenario", StringFormat("Drawdown Hist: %.1f%%", MaxDrawdownHistoric), COLOR_SPREAD);
   
   string estadoText;
   color estadoColor;
   if(ModoProteccionActivado) {
      estadoText = "MODO PROTECCIÓN ACTIVO";
      estadoColor = clrRed;
   } else if(InWaitingState) {
      int seg = MinDuration * 60 - (int)(TimeCurrent() - TimerStart);
      estadoText = "ESPERA: " + IntegerToString(seg) + "s";
      estadoColor = clrYellow;
   } else {
      estadoText = "VIGILANCIA";
      estadoColor = clrWhite;
   }
   UpdateChartLabel(chartId, "LblEstado", estadoText, estadoColor);
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
   
   // ✅ AHORA USA CurrentPrincipalPositions EN LUGAR DE GLOBAL
   // Registra el máximo de posiciones DEL EA PRINCIPAL
   if(CurrentPrincipalPositions > MaxHistoricPositions) 
      MaxHistoricPositions = CurrentPrincipalPositions;
      
   if(lossPercent > MaxHistoricLoss) MaxHistoricLoss = lossPercent;
   if(spread > MaxHistoricSpread) MaxHistoricSpread = spread;
   
   double drawdownActual = 100.0 - equityPercent;
   if(drawdownActual > MaxDrawdownHistoric)
   {
      MaxDrawdownHistoric = drawdownActual;
      BalanceAtMaxDrawdown = AccountBalance();
      double marginRequired = MarketInfo(TradingSymbol, MODE_MARGINREQUIRED);
      if(marginRequired > 0)
      {
         LoteMaxAtMaxDrawdown = (BalanceAtMaxDrawdown * MaxDrawdownHistoric / 100.0) / marginRequired;
         LoteMaxAtMaxDrawdown = MathMin(LoteMaxAtMaxDrawdown, LoteMaximo);
         LoteMaxAtMaxDrawdown = MathMax(LoteMaxAtMaxDrawdown, LoteMinimo);
         LoteMaxAtMaxDrawdown = NormalizeDouble(LoteMaxAtMaxDrawdown, 2);
      }
   }
}