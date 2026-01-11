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
input double   EquityThreshold = 60.0;    // % de equity sobre balance para activación
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
const int      MAX_POSICIONES_TOTAL = 10;       // Hard Cap de posiciones (Solo Paragua)
int            CurrentPrincipalPositions = 0;   // Para el monitor visual

// Parámetros para backtesting
input bool     Modo_Backtest = false;           // Activar modo backtesting
input datetime Fecha_Inicio_Backtest = D'2023.01.01'; // Fecha inicio backtest
input datetime Fecha_Fin_Backtest = D'2023.12.31';   // Fecha fin backtest

// --- NUEVOS PARÁMETROS TÉCNICOS ---
input int      ToleranciaPips = 20;      // Tolerancia para picos (Doble/Triple Techo-Piso)
input int      SegundosAgotamiento = 30; // Tiempo para confirmar agotamiento de tendencia
input double   MaxSpreadCierre = 30.0;   // No cerrar si el spread supera este valor
input bool     UsarNotificacionesPush = true;

// --- VARIABLES DE ESTADO PARA CIERRE ---
double   Precio_Referencia = 0.0;   // Sustituye a Precio_Referencia_Cierre
bool     Agotamiento_Activo = false; // Sustituye a Alerta_Cierre_Activada
datetime Timer_Gatillo = 0;         // Sustituye a Timer_Agotamiento
int      Seg_Agotamiento = 30;      // Segundos configurables (puedes usar un input)
double   Max_Spread_Op = 3.0;       // Límite de spread para cierre estructurado

// --- ESTRUCTURA DE PANTALLA ---
color          COLOR_TERCIO = clrOrange;
color          COLOR_PATRON = clrAqua;

// Variables globales
bool           InWaitingState = false;
datetime       TimerStart = 0;
int            RecoveryCount = 0;
bool           WasBelowThreshold = false;
int            CurrentOpenPositions = 0;
int            MaxHistoricPositions = 0;
double         MaxHistoricLoss = 0.0;
double         MaxHistoricSpread = 0.0;

// --- VARIABLES DE DISTANCIA ENTRE EXTREMOS ---
double DistanciaExtremosActual = 0.0; // Distancia % actual entre P_max y P_min
double MaxDistanciaHistorica = 0.0;   // Máximo histórico de distancia %

// Nuevas variables para la lógica de cobertura
bool           ModoProteccionActivado = false;
int            DireccionEAPrincipal = -1;
double         LoteFijo = 0.0;
double         UltimoEscalon = 0.0;
double         PisoActual = 0.0;
bool           GraficoCerrado = false;

// --- NUEVAS VARIABLES PARA LÓGICA DE CIERRE REGULADO ---
double         LoteInicialPrincipal = 0.0; // Lote total del Principal al 100% de la activación
bool           BloqueoAperturasActivo = false; // Bandera que indica el inicio de la fase de cierre
int            LadoCierreSiguiente = OP_BUY;   // -1: Principal (Inicial), OP_BUY/OP_SELL: Dirección a cerrar

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

// --- VARIABLES ADICIONALES PARA LÓGICA DE AGOTAMIENTO Y BALANZA ---
double   Max_DD_Ciclo = 0.0;
double   Vol_Ref = 0.0;  

// --- PARÁMETROS DE CIERRE VIERNES ---
input bool     FridayLogout = true;      // Activar cierre de seguridad los viernes
input int      LogoutHour = 21;          // Hora de inicio (Market Watch)
input int      LogoutMinute = 0;         // Minuto de inicio

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

//+------------------------------------------------------------------+
//| Función OnTimer                                                  |
//| Gestiona el monitoreo periódico, Friday Logout y reset semanal   |
//+------------------------------------------------------------------+
void OnTimer()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   
   CurrentOpenPositions = CountParaguaPositions();
   CurrentPrincipalPositions = CountPrincipalPositions(); 
   
   // Recalibración por distancia
   if(ModoProteccionActivado && (equityPercent - UltimoEscalon) >= 10.0)
   {
      PisoActual = equityPercent - 10.0;
      UltimoEscalon = equityPercent - 10.0;
      ConteoOrdenesSerie = 0;
      Print("🔄 RECALIBRACIÓN COMPLETA - Piso subió. Serie reseteada.");
   }
   
   // Lógica de Friday Logout (Solo si NO está en protección)
   if(FridayLogout && EsViernesNoche() && !ModoProteccionActivado)
   {
      int totalPos = CurrentPrincipalPositions + CurrentOpenPositions;
      if(totalPos == 0 && !GraficoCerrado)
      {
         CerrarGraficoXAUUSDConReintentos();
         GraficoCerrado = true;
      }
   }
   
   MonitoreoPrincipal(equityPercent, spread);
   VerificarRecuperacionEquity(equityPercent);
   UpdateAllChartsPanels(equityPercent, spread);
   GestionarResetDeteccion();
}

//+------------------------------------------------------------------+
//| Función de evento Tick (Motor Principal)                         |
//| Controla el monitoreo de niveles, temporizadores y cierres       |
//+------------------------------------------------------------------+
void OnTick()
{
   double equity = AccountEquity();
   double balance = AccountBalance();
   double equityPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();
   
   CurrentOpenPositions = CountParaguaPositions();
   CurrentPrincipalPositions = CountPrincipalPositions();
   
   if(ModoProteccionActivado && (equityPercent - UltimoEscalon) >= 10.0)
   {
      PisoActual = equityPercent - 10.0;
      UltimoEscalon = equityPercent - 10.0;
      ConteoOrdenesSerie = 0;
      Print("🔄 RECALIBRACIÓN - El piso subió 10%.");
   }
   
   MonitoreoPrincipal(equityPercent, spread);
   VerificarRecuperacionEquity(equityPercent);
   UpdateAllChartsPanels(equityPercent, spread);
   GestionarResetDeteccion();

   if(ModoProteccionActivado)
   {
      DeterminarNivelesReferencia();
      double currentDD = 100.0 - equityPercent;
      
      bool nivelTocado = (DireccionEAPrincipal == OP_BUY) ? (Bid >= Precio_Referencia) : (Ask <= Precio_Referencia);
      
      if(nivelTocado)
      {
         if(!Agotamiento_Activo)
         {
            Agotamiento_Activo = true;
            Timer_Gatillo = TimeCurrent();
            Max_DD_Ciclo = currentDD;
            Print("⚠️ Zona detectada. Iniciando timer de 30s.");
         }
         
         if(currentDD > Max_DD_Ciclo)
         {
            Max_DD_Ciclo = currentDD;
            Timer_Gatillo = TimeCurrent();
         }
         
         if(TimeCurrent() - Timer_Gatillo >= (uint)Seg_Agotamiento && currentDD < Max_DD_Ciclo)
         {
            Print("🎯 Agotamiento confirmado tras 30s. Intentando balancear.");
            EjecutarCierreEstructurado();
         }
      }
      else
      {
         if(Agotamiento_Activo && MathAbs(Bid - Precio_Referencia) > ToleranciaPips * Point * 3)
         {
            Agotamiento_Activo = false;
            Timer_Gatillo = 0;
         }
      }
   }
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

//+------------------------------------------------------------------+
//| Función de activación del modo protección                        |
//+------------------------------------------------------------------+
void ActivarModoProteccion()
{
   if(ModoProteccionActivado) return;
   
   // 1. Capturar Volumen de Referencia inmutable
   Vol_Ref = GetPrincipalTotalLot();
   if (Vol_Ref <= 0.0) {
      Print("Error: No se puede activar protección, Lote Principal es cero.");
      return;
   }
   
   // 2. Detección de dirección del EA Principal
   if(!DireccionDetectada)
   {
      if(!DetectarDireccionEAPrincipal()) return;
   }
   
   // 3. Definición del inicio del ciclo de cierre
   LadoCierreSiguiente = DireccionEAPrincipal;
   
   // 4. Cierre de gráficos operativos para evitar nuevas órdenes del Principal
   if(IsXAUUSDChartOpen())
   {
      if(!CerrarGraficoXAUUSDConReintentos()) return;
   }
   
   // 5. Cálculos de Lote Inicial y Niveles de Equity
   CalcularLoteInicial();
   double equity = AccountEquity();
   double balance = AccountBalance();
   PisoActual = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   UltimoEscalon = PisoActual;
   
   // 6. Registro del episodio y primera cobertura
   GuardarEpisodio();
   if(!AbrirCoberturaConReintentos()) return;
   
   // 7. Establecer estados finales de activación
   ModoProteccionActivado = true;
   InWaitingState = false;
   TimerStart = 0;
   GraficoCerrado = true;
   ConteoOrdenesSerie = 1; 
   
   string direccion = (DireccionEAPrincipal == OP_BUY) ? "BUY" : "SELL";
   string mensaje = StringFormat("MODO PROTECCIÓN ACTIVADO - Dir: %s - VolRef: %.2f - Piso: %.2f%%", 
                                direccion, Vol_Ref, PisoActual);
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
//| Obtener Lote Total Abierto del EA PRINCIPAL                      |
//| (Todo MENOS Magic 3030)                                          |
//+------------------------------------------------------------------+
double GetPrincipalTotalLot()
{
   double totalLot = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            // Ignorar mis propias órdenes de cobertura
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            totalLot += OrderLots(); // Sumar el lote
         }
      }
   }
   return totalLot;
}

//+------------------------------------------------------------------+
//| Obtener Lote Total Abierto del PROTECTOR (Magic 3030)            |
//+------------------------------------------------------------------+
double GetParaguaTotalLot()
{
   double totalLot = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         string orderSymbol = OrderSymbol();
         if(NormalizeSymbol(orderSymbol) == SymbolXAU)
         {
            // SOLO órdenes del protector (Magic Number)
            if(OrderMagicNumber() == Magic_Number) 
               totalLot += OrderLots(); // Sumar el lote
         }
      }
   }
   return totalLot;
}

void CalcularDistanciaOperativa()
{
   double pMax = 0.0;
   double pMin = 0.0;
   bool primeraOrden = true;

   // Recorrer todas las órdenes abiertas del terminal 
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) 
      {
         // Filtrar exclusivamente por el símbolo XAUUSD y excluir las órdenes del Protector (Magic 3030) 
         if(NormalizeSymbol(OrderSymbol()) == SymbolXAU && OrderMagicNumber() != Magic_Number)
         {
            double precioApertura = OrderOpenPrice();
            
            if(primeraOrden) {
               pMax = precioApertura;
               pMin = precioApertura; 
               primeraOrden = false;
            } else {
               if(precioApertura > pMax) pMax = precioApertura;
               if(precioApertura < pMin) pMin = precioApertura; 
            }
         }
      }
   }

   // Si se encontraron órdenes válidas, calcular el porcentaje 
   if(!primeraOrden && pMin > 0) {
      // Cálculo: ((Precio Máximo - Precio Mínimo) / Precio Mínimo) * 100
      DistanciaExtremosActual = ((pMax - pMin) / pMin) * 100.0; 
      
      // Actualizar el máximo histórico registrado 
      if(DistanciaExtremosActual > MaxDistanciaHistorica) {
         MaxDistanciaHistorica = DistanciaExtremosActual;
      }
   } else {
      // Si no hay órdenes del Principal, la distancia actual es cero
      DistanciaExtremosActual = 0.0;
   }
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
//| Gestionar modo protección (INCLUYE BLOQUEO Y CIERRE REGULADO)    |
//+------------------------------------------------------------------+
void ManageProtectionMode(double equityPercent)
{
   // 1. HARD CAP (Límite Global de Inventario)
   if(CountParaguaPositions() >= MAX_POSICIONES_TOTAL)
   {
      BloqueoAperturasActivo = true; // Forzar bloqueo si se alcanza el límite duro
      // Aún así, intentamos cerrar si hay oportunidad.
   }

   // --- LÓGICA DE BLOQUEO DE APERTURAS ---
   if (!BloqueoAperturasActivo) {
       
       double loteActualPrincipal = GetPrincipalTotalLot();
       double porcentajeRestanteP = (LoteInicialPrincipal > 0.0) ? (loteActualPrincipal / LoteInicialPrincipal) * 100.0 : 100.0;
       
       // Bloquear si se alcanza el límite duro O si el Principal ha reducido su carga en 35% (65% restante)
       if (CountParaguaPositions() >= MAX_POSICIONES_TOTAL || porcentajeRestanteP <= 65.0) {
           BloqueoAperturasActivo = true;
           Print("🔒 BLOQUEO DE APERTURAS ACTIVO. Inicio de fase de cierre regulado.");
       }
   }
   
   // --- APERTURA DE COBERTURAS (SOLO SI NO ESTÁ BLOQUEADO) ---
   if (!BloqueoAperturasActivo)
   {
       // Obtener distancia requerida según el paso de la serie
       double distanciaRequerida = ObtenerDistanciaProximoEscalon();
       
       // Verificar si el precio cayó la distancia requerida
       if(equityPercent <= UltimoEscalon - distanciaRequerida)
       {
          if(AbrirCoberturaConReintentos())
          {
             UltimoEscalon = UltimoEscalon - distanciaRequerida;
             ConteoOrdenesSerie++; // Avanzamos un paso en la secuencia
             Print(StringFormat("Nueva cobertura (Paso Serie: %d) - Distancia: %.1f%% - Nuevo Escalón: %.2f%%", 
                               ConteoOrdenesSerie, distanciaRequerida, UltimoEscalon));
          }
       }
       return; // Sale si sigue abriendo coberturas
   }   
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
   RecoveryCount = 0;
   MaxHistoricPositions = 0;
   MaxHistoricLoss = 0.0;
   MaxHistoricSpread = 0.0;
   DistanciaExtremosActual = 0.0;
   MaxDistanciaHistorica = 0.0;
   
   EpisodioDireccion = -1;
   EpisodioLoteBase = 0.0;
   EpisodioUltimoEscalon = 0.0;
   EpisodioPisoActual = 0.0;
   EpisodioInicio = 0;
   ConteoOrdenesSerie = 0;

   if(GlobalVariableCheck("Protector_RecoveryCount")) 
      RecoveryCount = (int)GlobalVariableGet("Protector_RecoveryCount");
   if(GlobalVariableCheck("Protector_MaxPositions")) 
      MaxHistoricPositions = (int)GlobalVariableGet("Protector_MaxPositions");
   if(GlobalVariableCheck("Protector_MaxLoss")) 
      MaxHistoricLoss = GlobalVariableGet("Protector_MaxLoss");
   if(GlobalVariableCheck("Protector_MaxSpread")) 
      MaxHistoricSpread = GlobalVariableGet("Protector_MaxSpread");

   if(GlobalVariableCheck("Protector_MaxDistancia")) 
      MaxDistanciaHistorica = GlobalVariableGet("Protector_MaxDistancia");

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
   if(GlobalVariableCheck("Protector_ConteoSerie"))
      ConteoOrdenesSerie = (int)GlobalVariableGet("Protector_ConteoSerie");

   if(GlobalVariableCheck("Protector_DireccionDetectada")) 
      DireccionDetectada = (bool)GlobalVariableGet("Protector_DireccionDetectada");
   if(GlobalVariableCheck("Protector_TiempoDeteccion")) 
      TiempoDeteccion = (datetime)GlobalVariableGet("Protector_TiempoDeteccion");

   if(EpisodioDireccion != -1 && EpisodioInicio > 0)
   {
      ModoProteccionActivado = true;
      DireccionEAPrincipal = EpisodioDireccion;
      LoteFijo = EpisodioLoteBase;
      UltimoEscalon = EpisodioUltimoEscalon;
      PisoActual = EpisodioPisoActual;
      
      Print("SISTEMA RESTAURADO: Modo Proteccion Activo");
   }
   
   if(ModoProteccionActivado && DireccionDetectada)
   {
      if(DireccionEAPrincipal != EpisodioDireccion)
      {
         DireccionEAPrincipal = EpisodioDireccion;
      }
   }
}

//+------------------------------------------------------------------+
//| Guardar datos persistentes                                       |
//+------------------------------------------------------------------+
void SavePersistentData()
{
   GlobalVariableSet("Protector_RecoveryCount", (double)RecoveryCount);
   GlobalVariableSet("Protector_MaxPositions", (double)MaxHistoricPositions);
   GlobalVariableSet("Protector_MaxLoss", MaxHistoricLoss);
   GlobalVariableSet("Protector_MaxSpread", MaxHistoricSpread);
   
   GlobalVariableSet("Protector_MaxDistancia", MaxDistanciaHistorica);
   
   if(ModoProteccionActivado)
   {
      GlobalVariableSet("Protector_EpisodioDireccion", (double)EpisodioDireccion);
      GlobalVariableSet("Protector_EpisodioLoteBase", EpisodioLoteBase);
      GlobalVariableSet("Protector_EpisodioUltimoEscalon", EpisodioUltimoEscalon);
      GlobalVariableSet("Protector_EpisodioPisoActual", EpisodioPisoActual);
      GlobalVariableSet("Protector_EpisodioInicio", (double)EpisodioInicio);
      GlobalVariableSet("Protector_ConteoSerie", (double)ConteoOrdenesSerie);
   }
   else
   {
      GlobalVariableSet("Protector_EpisodioDireccion", -1.0);
      GlobalVariableSet("Protector_ConteoSerie", 0.0);
   }
   
   GlobalVariableSet("Protector_DireccionDetectada", (double)DireccionDetectada);
   GlobalVariableSet("Protector_TiempoDeteccion", (double)TiempoDeteccion);
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
//| Ejecuta el cierre de un lote específico (Parcial o Total)        |
//+------------------------------------------------------------------+
bool ClosePartialLot(int type, double lotToClose)
{
    double lotRemaining = lotToClose;
    bool success = false;
    
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        if(lotRemaining <= 0) break;
        
        if(OrderSelect(i, SELECT_BY_POS)) 
        {
            if(NormalizeSymbol(OrderSymbol()) == SymbolXAU && OrderType() == type)
            {
                double lot = OrderLots();
                double closeLot = MathMin(lot, lotRemaining);
                
                bool isParagua = (OrderMagicNumber() == Magic_Number);
                
                // Si es orden del protector, solo cerramos si es la unidad completa
                if (isParagua && closeLot < lot) continue;
                
                if(OrderClose(OrderTicket(), closeLot, OrderClosePrice(), 3, clrNONE)) 
                {
                    lotRemaining -= closeLot;
                    success = true;
                }
            }
        }
    }
    return success;
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

void DeterminarNivelesReferencia()
{
   double pMax = 0.0, pMin = 0.0;
   bool hayOrdenes = false;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() != Magic_Number)
      {
         double openP = OrderOpenPrice();
         if(!hayOrdenes) { pMax = openP; pMin = openP; hayOrdenes = true; }
         else { pMax = MathMax(pMax, openP); pMin = MathMin(pMin, openP); }
      }
   }

   if(!hayOrdenes) return;

   int picosEncontrados = 0;
   for(int i = 1; i < 50; i++)
   {
      double diff = MathAbs(High[i] - pMax);
      if(diff <= ToleranciaPips * Point) picosEncontrados++;
   }

   if(picosEncontrados >= 3)
   {
      Precio_Referencia = pMax;
      ObjectCreate(0, "Linea_Triple", OBJ_HLINE, 0, 0, Precio_Referencia);
      ObjectSetInteger(0, "Linea_Triple", OBJPROP_COLOR, clrAqua);
   }
   else
   {
      double rango = pMax - pMin;
      Precio_Referencia = (DireccionEAPrincipal == OP_BUY) ? pMax - (rango / 3.0) : pMin + (rango / 3.0);
      ObjectCreate(0, "Linea_Tercio", OBJ_HLINE, 0, 0, Precio_Referencia);
      ObjectSetInteger(0, "Linea_Tercio", OBJPROP_COLOR, clrOrange);
   }
}

bool ValidarBalanza(double loteACerrar, int tipoOrden)
{
   double loteActualP = GetPrincipalTotalLot();
   double loteActualC = GetParaguaTotalLot();
   
   if(Vol_Ref <= 0) Vol_Ref = loteActualP;

   // Porcentajes cerrados actuales
   double p_cerrado = ((Vol_Ref - loteActualP) / Vol_Ref) * 100.0;
   double c_cerrado = (MathMax(0, (LoteFijo * 10.0) - loteActualC) / Vol_Ref) * 100.0;
   
   double brechaActual = MathAbs(p_cerrado - c_cerrado);
   
   // Simulación de brecha futura
   double p_futuro = (tipoOrden == DireccionEAPrincipal) ? ((Vol_Ref - (loteActualP - loteACerrar)) / Vol_Ref) * 100.0 : p_cerrado;
   double c_futuro = (tipoOrden != DireccionEAPrincipal) ? ((Vol_Ref - (loteActualC - loteACerrar)) / Vol_Ref) * 100.0 : c_cerrado;
   double brechaFutura = MathAbs(p_futuro - c_futuro);

   if(brechaActual > 35.0) 
      return (brechaFutura < brechaActual); // Debe converger
   
   return (brechaFutura <= 35.0); // Debe mantenerse en zona segura
}

void EjecutarCierreEstructurado()
{
   if(GetSpreadForXAUUSD() > Max_Spread_Op) return;

   int tipoACerrar = LadoCierreSiguiente;
   double loteBase = (tipoACerrar == DireccionEAPrincipal) ? LoteMinimo : LoteFijo;

   // 1. Validar si la balanza permite este cierre
   if(ValidarBalanza(loteBase, tipoACerrar))
   {
      // 2. Cerrar solo si tiene Profit Neto > 0
      for(int i = OrdersTotal()-1; i >= 0; i--)
      {
         if(OrderSelect(i, SELECT_BY_POS) && OrderType() == tipoACerrar)
         {
            double neto = OrderProfit() + OrderCommission() + OrderSwap();
            if(neto > 0)
            {
               if(OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3))
               {
                  Print("Cierre realizado con éxito tras agotamiento");
                  // Alternar lado para mantener balance
                  LadoCierreSiguiente = (tipoACerrar == OP_BUY) ? OP_SELL : OP_BUY;
                  break; 
               }
            }
         }
      }
   }
   
   // Resetear estado tras intento
   Agotamiento_Activo = false;
   Timer_Gatillo = 0;
}

//+------------------------------------------------------------------+
//| Eliminar panel visual DE TODOS LOS GRÁFICOS                     |
//+------------------------------------------------------------------+
void DeleteMonitoringPanel()
{
   // Lista de nombres de objetos a eliminar
   string obj_names[] = {
      "PanelBG", "LblPositions", "LblLoss", "LblMaxLoss", 
      "LblRecoveries", "LblSpread", "LblMaxSpread", 
      "LblPeorEscenario", "LblMaxDistancia", "LblEstado", 
      "LblSpreadSet", "LblMargen", "LblBalance"
   };

   // 1. Eliminar objetos de TODOS los gráficos abiertos
   long chartId = ChartFirst();
   int chartCount = 0;
   
   while(chartId >= 0 && chartCount < 100) 
   {
      for(int i = 0; i < ArraySize(obj_names); i++)
      {
         ObjectDelete(chartId, obj_names[i]);
      }
      
      chartId = ChartNext(chartId);
      chartCount++;
   }
   
   // 2. Limpieza final en el gráfico actual
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
   int spacing = 22; // Espaciado ligeramente reducido para optimizar espacio
   
   long chartId = ChartFirst();
   while(chartId >= 0) {
      // 1. Fondo del panel
      ObjectCreate(chartId, "PanelBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XDISTANCE, x - 10);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YDISTANCE, y - 5);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XSIZE, 300);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YSIZE, 240); // Aumentado para nueva línea 
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_BGCOLOR, PANEL_BG); 
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_BACK, true);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_SELECTABLE, false);

      // 2. Etiquetas de Monitoreo Estándar
      CreateChartLabel(chartId, "LblPositions", "Posiciones: ", x, y, COLOR_POSITIONS); 
      CreateChartLabel(chartId, "LblLoss", "Pérdida: ", x, y + spacing, COLOR_LOSS); 
      CreateChartLabel(chartId, "LblMaxLoss", "Pérdida Máx: ", x, y + spacing*2, COLOR_MAX_VALUES); 
      CreateChartLabel(chartId, "LblRecoveries", "Recuperaciones: ", x, y + spacing*3, COLOR_RECOVERY); 
      
      // 3. Etiquetas de Spread
      CreateChartLabel(chartId, "LblSpread", "Spread Actual: ", x, y + spacing*4, COLOR_SPREAD); 
      CreateChartLabel(chartId, "LblMaxSpread", "Spread Máx Hist: ", x, y + spacing*5, COLOR_MAX_VALUES); 
      
      // 4. NUEVA SECCIÓN: Distancia entre Extremos (Color Cyan)
      // Línea de Distancia Actual
      CreateChartLabel(chartId, "LblPeorEscenario", "Distancia Ext: ", x, y + spacing*6, COLOR_SPREAD);
      // Línea de Máximo Histórico de Distancia
      CreateChartLabel(chartId, "LblMaxDistancia", "Max Distancia: ", x, y + spacing*7, COLOR_MAX_VALUES);
      
      // 5. Estado del Sistema
      CreateChartLabel(chartId, "LblEstado", "Estado: ", x, y + spacing*8, COLOR_MARGEN);
      
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
   // 1. Cálculos de Ganancia/Pérdida de la cuenta
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
   
   // 2. Actualización de Etiquetas Estándar
   UpdateChartLabel(chartId, "LblPositions", "Posiciones: " + IntegerToString(CurrentPrincipalPositions) + " | Máx: " + IntegerToString(MaxHistoricPositions));
   UpdateChartLabel(chartId, "LblLoss", lossGainText, lossGainColor); 
   UpdateChartLabel(chartId, "LblMaxLoss", "Pérdida Máx Hist: " + DoubleToString(MaxHistoricLoss, 2) + "%");
   UpdateChartLabel(chartId, "LblSpread", "Spread: " + DoubleToString(spread, 1)); 
   UpdateChartLabel(chartId, "LblMaxSpread", "Máx Spread: " + DoubleToString(MaxHistoricSpread, 1));
   UpdateChartLabel(chartId, "LblRecoveries", "Recuperaciones: " + IntegerToString(RecoveryCount)); 

   // 3. Distancia entre Extremos
   UpdateChartLabel(chartId, "LblPeorEscenario", StringFormat("Distancia Ext: %.2f%%", DistanciaExtremosActual), COLOR_SPREAD);
   UpdateChartLabel(chartId, "LblMaxDistancia", StringFormat("Max Distancia: %.2f%%", MaxDistanciaHistorica), COLOR_MAX_VALUES);

   // 4. Lógica de Estado del Sistema (Jerarquía de Seguridad)
   string estadoText;
   color estadoColor;

   // ESTADO A: Modo Protección Activo (Prioridad Máxima)
   if(ModoProteccionActivado) { 
      double pisoLoss = 100.0 - PisoActual;
      estadoText = "PROTECCIÓN ACTIVO: "+ DoubleToString(pisoLoss, 2) + "%";
      estadoColor = clrRed;
   } 
   // ESTADO B: Friday Logout (Solo si está en Vigilancia)
   else if(FridayLogout && EsViernesNoche()) {
      int totalPos = CurrentPrincipalPositions + CountParaguaPositions();
      
      if(totalPos > 0) {
         estadoText = "FRIDAY: ESPERANDO CIERRE (" + IntegerToString(totalPos) + ")";
         estadoColor = clrOrange;
      } else {
         estadoText = "FRIDAY: EJECUTANDO SALIDA";
         estadoColor = clrSalmon;
         
         if(!GraficoCerrado) {
            Print("Friday Logout: Posiciones en cero. Procediendo a cerrar gráficos.");
            CerrarGraficoXAUUSDConReintentos();
            GraficoCerrado = true;
         }
      }
   }
   // ESTADO C: Espera de activación (Temporizador)
   else if(InWaitingState) { 
      int seg = MinDuration * 60 - (int)(TimeCurrent() - TimerStart);
      estadoText = "ESPERA: " + IntegerToString(seg) + "s";
      estadoColor = clrYellow;
   } 
   // ESTADO D: Vigilancia Normal
   else {
      double lossThreshold = 100.0 - EquityThreshold;
      estadoText = "VIGILANCIA: "+ DoubleToString(lossThreshold, 2) + "%";
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
   // 1. Calcular pérdida actual basada en el Equity 
   double lossPercent = 100.0 - equityPercent; 
   
   // 2. Registrar el máximo de posiciones abiertas por el EA PRINCIPAL 
   if(CurrentPrincipalPositions > MaxHistoricPositions) 
      MaxHistoricPositions = CurrentPrincipalPositions; 
      
   // 3. Registrar el récord de pérdida (Drawdown de Equity) 
   if(lossPercent > MaxHistoricLoss) 
      MaxHistoricLoss = lossPercent; 
      
   // 4. Registrar el Spread máximo detectado 
   if(spread > MaxHistoricSpread) 
      MaxHistoricSpread = spread;

   // 5. Calcular la distancia entre extremos de la malla (Grid)
   // Esto actualiza DistanciaExtremosActual y MaxDistanciaHistorica para el monitor
   CalcularDistanciaOperativa();
}

//+------------------------------------------------------------------+
//| Función EsViernesNoche                                           |
//| Detecta si se ha alcanzado el horario de cierre del viernes      |
//+------------------------------------------------------------------+
bool EsViernesNoche()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5) // 5 = Viernes
   {
      if(dt.hour > LogoutHour || (dt.hour == LogoutHour && dt.min >= LogoutMinute))
         return true;
   }
   return false;
}