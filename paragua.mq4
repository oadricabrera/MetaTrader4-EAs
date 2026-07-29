//+------------------------------------------------------------------+
//|                                                       Paragua.mq4 |
//|                        Basado en Account Protector de EarnForex   |
//|                                  Versión especializada para XAUUSD|
//+------------------------------------------------------------------+
#property copyright "Adaptación especializada para estrategias grid en XAUUSD"
#property link      "https://github.com/EarnForex/Account-Protector"
#property version   "1.00"
#property strict

// --- VARIABLES FALTANTES DECLARADAS ---
bool Agotamiento_Confirmado = false; // Variable para el motor de agotamiento
int Counter = 0;                    // Contador para optimización de OnTick

// Parámetros configurables
input double   EquityThreshold = 70.0;    // % de equity sobre balance para activación
input int      MinDuration = 3;           // Minutos de persistencia para activación
input double   MaxSpread = 25.0;          // Spread máximo en pips para display
input int      Magic_Number = 3030;       // Magic number para las órdenes del protector
input string   SoundFile = "alert.wav";   // Archivo de sonido para alarma
input int      TimerInterval = 60;        // Segundos entre ejecuciones de OnTimer()

// --- SISTEMA DE BALANZA Y EXPANSIÓN (NUEVAS VARIABLES) ---
int    MaxPosicionesBase      = 10;    // Define el 100% del Paragua
datetime InicioAgotamiento    = 0;     // Timer de 30 segundos

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
int            CurrentPrincipalPositions = 0;   // Para el monitor visual

// Parámetros para backtesting
input bool     Modo_Backtest = false;           // Activar modo backtesting
input datetime Fecha_Inicio_Backtest = D'2023.01.01'; // Fecha inicio backtest
input datetime Fecha_Fin_Backtest = D'2023.12.31';   // Fecha fin backtest

// --- NUEVOS PARÁMETROS TÉCNICOS ---
input int      ToleranciaPips = 50;      // Tolerancia para picos (Doble/Triple Techo-Piso)
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
int            LadoCierreSiguiente = -1;
datetime       UltimaActualizacionPrecio = 0;  // Control de frecuencia de refresco

// --- VARIABLES DE DISTANCIA ENTRE EXTREMOS ---
double DistanciaExtremosActual = 0.0; // Distancia % actual entre P_max y P_min
double MaxDistanciaHistorica = 0.0;   // Máximo histórico de distancia %

// Nuevas variables para la lógica de cobertura
bool           ModoProteccionActivado = false;
bool           ModoPrecaucionActivado = false;
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

// AGREGAR PARÁMETRO DE CONFIGURACIÓN Notificaciones
input bool     Habilitar_Notificaciones = false;  // Enviar emails/notificaciones?
input bool     Habilitar_Alertas_Sonido = true;   // Reproducir sonidos de alerta?

// --- VARIABLES ADICIONALES PARA LÓGICA DE AGOTAMIENTO Y BALANZA ---
double   Max_DD_Ciclo = 0.0;
double   Vol_Ref = 0.0;
int      N_Principal = 0;        // Cantidad de posiciones del Principal al inicio del episodio
double   Vol_Total_Paragua = 0.0;
bool     Bloqueo_11_Plus = false;

// --- PARÁMETROS DE CIERRE VIERNES ---
input bool     FridayLogout = true;      // Activar cierre de seguridad los viernes
input int      LogoutHour = 21;          // Hora de inicio (Market Watch)
input int      LogoutMinute = 0;         // Minuto de inicio

//+------------------------------------------------------------------+
//| Función de inicialización                                        |
//+------------------------------------------------------------------+
int OnInit() {
   // --- CORRECCIÓN CRÍTICA: Asignar TradingSymbol al símbolo real de Oro ---
   TradingSymbol = GetTradingSymbol();
   SymbolXAU = NormalizeSymbol(TradingSymbol);
   
   // --- CORRECCIÓN: Validación universal sin importar el nombre del símbolo ---
   if(TradingSymbol == "" || !SymbolSelect(TradingSymbol, true))
   {
      Print("ERROR: No se pudo encontrar el símbolo de Oro. El Paragua no funcionará.");
      return(INIT_FAILED);
   }
   
   // 1. CARGAR DATOS PERSISTENTES
   LoadPersistentData();
   
   // 2. INICIALIZAR TRACKERS
   double eq = (AccountBalance() > 0) ? (AccountEquity() / AccountBalance()) * 100.0 : 100.0;
   UpdateHistoricalTrackers(eq, GetSpreadForXAUUSD());

   DeleteMonitoringPanel();
   CreateMonitoringPanel();
   
   EventSetTimer(TimerInterval);
   Print("Protector Iniciado. Símbolo de trading: ", TradingSymbol, " | Datos cargados.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Función de desinicialización                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer(); // Detiene el reloj para que no consuma recursos
   Print("Protector Finalizado. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Funcion de evento Tick (Motor Principal)                         |
//| Controla el flujo:                                               |
//|   Precaución -> Vigilia -> Espera -> Proteccion -> Cierre        |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Datos basicos de la cuenta
   double balance = AccountBalance();
   double equity  = AccountEquity();
   double eqPercent = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   double spread = GetSpreadForXAUUSD();

   // 2. Actualizar estadisticas historicas y panel
   UpdateHistoricalTrackers(eqPercent, spread);

   // 3. MODO PRECAUCION: estado congelado (solo actualiza el panel)
   if(ModoPrecaucionActivado)
   {
      if(Counter % 10 == 0)
         UpdateAllChartsPanels(eqPercent, spread);
      Counter++;
      return; // No hace nada mas mientras esta en precaucion
   }

   // 4. Logica principal de estados
   if(!ModoProteccionActivado)
   {
      // --- ESTADO VIGILIA ---
      // Monitorea si el equity cae por debajo del umbral
      CheckActivationConditions(eqPercent);
   }
   else
   {
      // --- ESTADO PROTECCION ACTIVA ---
      if(CountParaguaPositions() == 0)
      {
         if(Vol_Ref <= 0) Vol_Ref = GlobalVariableGet("Prot_VolRef");
         CalcularLoteInicial();
         
         // --- CORRECCIÓN: Forzar refresco de precios de XAUUSD antes de abrir ---
         if(!RefreshXAUUSDPrice())
         {
            Print("Error: No se pudo refrescar precios de XAUUSD. Reintentando en próximo tick.");
            return;
         }
         
         if(AbrirCoberturaConReintentos())
         {
            ConteoOrdenesSerie = 1;
            SavePersistentData();
            Print("INSISTENCIA: Primera orden de proteccion colocada con exito.");
         }
         return;
      }

      // Cerrar graficos del EA Principal si estan abiertos
      if(IsXAUUSDChartOpen())
         CerrarGraficoXAUUSDConReintentos();

      // Actualizar piso minimo de equity
      if(eqPercent < PisoActual)
         PisoActual = eqPercent;

      // Recalibracion por repunte del 10%
      if(eqPercent >= PisoActual + 10.0)
      {
         UltimoEscalon = eqPercent;
         PisoActual = eqPercent;
         ConteoOrdenesSerie = 0;
         Print("Recalibracion 10% activada. Reiniciando a Serie A.");
         SavePersistentData();
      }

      // Gestion de apertura de nuevas coberturas (escalonamiento)
      ManageProtectionMode(eqPercent);

      // Deteccion de agotamiento de tendencia
      DeterminarNivelesReferencia();

      // Ejecutar cierre estructurado si hay agotamiento
      if(Agotamiento_Confirmado)
      {
         EjecutarCierreEstructurado();
         LimpiarExcesoParagua();
      }

      // Verificar si el equity se recupero naturalmente
      VerificarRecuperacionEquity(eqPercent);
   }

   // Actualizar distancia operativa entre extremos
   CalcularDistanciaOperativa();

   // Actualizacion visual del panel (cada 10 ticks)
   if(Counter % 10 == 0)
      UpdateAllChartsPanels(eqPercent, spread);

   Counter++;
}

//+------------------------------------------------------------------+
//| Verificación continua de recuperación de equity                 |
//+------------------------------------------------------------------+
void VerificarRecuperacionEquity(double equityPercent)
{
    if(ModoProteccionActivado && equityPercent > EquityThreshold)
    {
        Print("EQUITY RECUPERADO - Volviendo a modo vigilia");
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
   if(ModoProteccionActivado) return;
   if(ModoPrecaucionActivado) return;   // Si ya está en precaución, no hacer nada
   
   if(equityPercent > EquityThreshold)
   {
      InWaitingState = false;
      TimerStart = 0;
      return;
   }
   
   // Equity por debajo del umbral
   if(!InWaitingState)
   {
      TimerStart = TimeCurrent();
      InWaitingState = true;
      Print("VIGILIA: Equity por debajo del umbral (", equityPercent, "%). Temporizador iniciado.");
      return;
   }
   
   // Verificar si ya pasó el tiempo de persistencia
   if(InWaitingState && (TimeCurrent() - TimerStart >= MinDuration * 60))
   {
      // NUEVA VALIDACION: Verificar si el EA Principal tiene posiciones
      if(CountPrincipalPositions() == 0)
      {
         Print("PRECAUCION: Temporizador completado pero EA Principal sin posiciones. Activando modo precaucion.");
         ActivarModoPrecaucion();
         return;
      }
      
      // Si tiene posiciones, activar proteccion normal
      Print("TRANSICION: Temporizador completado. Activando proteccion...");
      ActivarModoProteccion();
   }
}

//+------------------------------------------------------------------+
//| Verificar si hay gráficos XAUUSD abiertos (NUEVA)               |
//+------------------------------------------------------------------+
bool IsXAUUSDChartOpen()
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      // Comparamos el "ADN" del símbolo del gráfico contra nuestro identificador de Oro
      if(NormalizeSymbol(ChartSymbol(chartId)) == "XAU_FOUND")
         return true;
         
      chartId = ChartNext(chartId);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Función de activación del modo protección                        |
//+------------------------------------------------------------------+
void ActivarModoProteccion()
{
   if(ModoProteccionActivado) return;
   
   // --- PRIORIDAD DE MANDO: ACTIVACIÓN INSTANTÁNEA ---
   ModoProteccionActivado = true;
   InWaitingState = false;
   SavePersistentData();
   
   Vol_Ref = GetPrincipalTotalLot();
   N_Principal = CountPrincipalPositions();
   if (Vol_Ref <= 0.0) 
   {
      Print("Error: No se puede activar proteccion, Lote Principal es cero.");
      ModoProteccionActivado = false;
      return;
   }

   // --- REGLA DE SECUESTRO ---
   if(!DireccionDetectada) 
   {
      DetectarDireccionEAPrincipal();
   }
   LadoCierreSiguiente = DireccionEAPrincipal;
   Print("Direccion capturada y Vol_Ref guardado: ", Vol_Ref);

   if(IsXAUUSDChartOpen()) 
   {
      CerrarGraficoXAUUSDConReintentos();
   }

   CalcularLoteInicial(); // Garantiza el 10%

   // --- CORRECCIÓN: Forzar refresco de precios de XAUUSD antes de la Serie A ---
   if(!RefreshXAUUSDPrice())
   {
      Print("Error: No se pudo refrescar precios de XAUUSD. La cobertura podría fallar.");
   }

   AbrirCoberturaConReintentos();
   Print("Orden 1 de Serie A enviada");

   double equity = AccountEquity();
   double balance = AccountBalance();
   
   PisoActual = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
   UltimoEscalon = PisoActual;

   TimerStart = 0;
   GraficoCerrado = true;
   ConteoOrdenesSerie = 1;

   GuardarEpisodio();
   SavePersistentData();

   string direccion = (DireccionEAPrincipal == OP_BUY) ? "BUY" : "SELL";
   string mensaje = StringFormat("ESTADO: PROTECCION ACTIVA - Dir: %s - Vol_Ref: %.2f - Piso: %.2f%%", direccion, Vol_Ref, PisoActual);
   
   if(Habilitar_Notificaciones) SendNotifications(mensaje);
   if(Habilitar_Alertas_Sonido) PlayAlarmSound();
   
   Print(mensaje);
}

//+------------------------------------------------------------------+
//| ActivarModoPrecaucion()                                          |
//| Descripcion:                                                     |
//|   Estado intermedio entre Vigilia y Proteccion.                  |
//|   Se activa cuando el temporizador (MinDuration) expira,         |
//|   pero el EA Principal no tiene posiciones abiertas.             |
//|                                                                  |
//| Acciones:                                                        |
//|   1. Cierra el grafico de XAUUSDp (si existe)                    |
//|   2. NO abre coberturas                                          |
//|   3. Congela el estado (no vuelve automaticamente a vigilia)    |
//|   4. Muestra "PRECAUCION: XX.X%" en el panel (color naranja)     |
//|                                                                  |
//| Persistencia:                                                    |
//|   Este estado NO se guarda en GlobalVariables.                   |
//|   Si el EA se reinicia, empezara en Modo Vigilia.                |
//|                                                                  |
//| Notificaciones:                                                  |
//|   - Envia email/push si Habilitar_Notificaciones = true          |
//|   - Reproduce sonido si Habilitar_Alertas_Sonido = true          |
//+------------------------------------------------------------------+
void ActivarModoPrecaucion()
{
   // Evitar activaciones multiples o conflictos con otros modos
   if(ModoPrecaucionActivado) return;
   if(ModoProteccionActivado) return;
   
   // Establecer el estado
   ModoPrecaucionActivado = true;
   InWaitingState = false;   // Resetea el temporizador de espera
   TimerStart = 0;
   
   // Registrar en el log del EA
   Print("MODO PRECAUCION ACTIVADO - Cerrando grafico XAUUSDp sin abrir coberturas");
   
   // Cerrar el grafico del EA Principal si esta abierto
   if(IsXAUUSDChartOpen())
   {
      CerrarGraficoXAUUSDConReintentos();
   }
   
   // IMPORTANTE: NO se abren coberturas
   // IMPORTANTE: NO se guarda en persistent data (por diseño)
   
   // Enviar notificaciones si estan habilitadas
   if(Habilitar_Notificaciones) 
   {
      double equityActual = AccountEquity();
      SendNotifications("MODO PRECAUCION ACTIVADO - Equity: " + DoubleToString(equityActual, 2) + " USD");
   }
   
   // Reproducir sonido de alerta si esta habilitado
   if(Habilitar_Alertas_Sonido) 
      PlayAlarmSound();
}

//+------------------------------------------------------------------+
//| Contar posiciones EXCLUSIVAS del Paragua                         |
//+------------------------------------------------------------------+
int CountParaguaPositions()
{
   int count = 0;
   if(TradingSymbol == "") return 0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Contar posiciones del EA PRINCIPAL                               |
//+------------------------------------------------------------------+
int CountPrincipalPositions()
{
   int count = 0;
   if(TradingSymbol == "") return 0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            count++; 
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
   if(TradingSymbol == "") return 0.0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            totalLot += OrderLots(); 
         }
      }
   }
   return NormalizeDouble(totalLot, 2);
}

//+------------------------------------------------------------------+
//| Obtener Lote Total Abierto del PROTECTOR (Magic 3030)            |
//+------------------------------------------------------------------+
double GetParaguaTotalLot()
{
   double totalLot = 0.0;
   if(TradingSymbol == "") return 0.0;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number) 
               totalLot += OrderLots();
         }
      }
   }
   return totalLot;
}

//+------------------------------------------------------------------+
//| CalcularDistanciaOperativa                                       |
//+------------------------------------------------------------------+
void CalcularDistanciaOperativa()
{
   double pMax = 0.0;
   double pMin = 0.0;
   bool hayOrdenes = false;
   if(TradingSymbol == "") return;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) 
      {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol) && OrderMagicNumber() != Magic_Number)
         {
            double precioApertura = OrderOpenPrice();
            if(!hayOrdenes) {
                pMax = precioApertura; 
                pMin = precioApertura; 
                hayOrdenes = true;
            } else {
                if(precioApertura > pMax) pMax = precioApertura;
                if(precioApertura < pMin) pMin = precioApertura; 
            }
         }
      }
   }

   if(hayOrdenes && pMin > 0) {
      DistanciaExtremosActual = ((pMax - pMin) / pMin) * 100.0; 
      if(DistanciaExtremosActual > MaxDistanciaHistorica) {
          MaxDistanciaHistorica = DistanciaExtremosActual;
          GlobalVariableSet("Protector_MaxDistancia", MaxDistanciaHistorica);
      }
   } else {
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
   GlobalVariableSet("Protector_VolRef", Vol_Ref);
   GlobalVariableSet("Protector_N_Principal", N_Principal);
   GlobalVariableSet("Protector_VolTP", Vol_Total_Paragua);
   GlobalVariableSet("Protector_Bloqueo11", Bloqueo_11_Plus ? 1.0 : 0.0);
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
   Vol_Ref = 0.0;
   Vol_Total_Paragua = 0.0;
   Bloqueo_11_Plus = false;
   
   InWaitingState = false;
   TimerStart = 0;
   
   // RESET DE VARIABLES DE SERIE
   ConteoOrdenesSerie = 0;
   
   GlobalVariableSet("Protector_EpisodioDireccion", -1);
   GlobalVariableSet("Protector_EpisodioLoteBase", 0.0);
   GlobalVariableSet("Protector_EpisodioUltimoEscalon", 0.0);
   GlobalVariableSet("Protector_EpisodioPisoActual", 0.0);
   GlobalVariableSet("Protector_EpisodioInicio", 0);
   GlobalVariableSet("Protector_ConteoSerie", 0.0); 
   GlobalVariableSet("Protector_VolRef", 0.0);
   GlobalVariableSet("Protector_VolTP", 0.0);
   GlobalVariableSet("Protector_Bloqueo11", 0.0);
   
   Print("Episodio de proteccion COMPLETAMENTE reseteado");
}

//+------------------------------------------------------------------+
//| Guardar datos persistentes                                       |
//+------------------------------------------------------------------+
void SavePersistentData()
{
   GlobalVariableSet("Prot_ModoActivo", (double)ModoProteccionActivado);
   GlobalVariableSet("Prot_ConteoSerie", (double)ConteoOrdenesSerie);
   GlobalVariableSet("Prot_PisoActual", PisoActual);
   GlobalVariableSet("Prot_UltimoEscalon", UltimoEscalon);
   GlobalVariableSet("Prot_VolRef", Vol_Ref);
   GlobalVariableSet("Prot_VolTP", Vol_Total_Paragua);
   GlobalVariableSet("Prot_MaxLoss", MaxHistoricLoss);
   GlobalVariableSet("Prot_Recovery", (double)RecoveryCount);
   GlobalVariableSet("Prot_Bloqueo11", Bloqueo_11_Plus ? 1.0 : 0.0);
}

void LoadPersistentData()
{
   if(GlobalVariableCheck("Prot_ModoActivo"))
      ModoProteccionActivado = (bool)GlobalVariableGet("Prot_ModoActivo");
   if(GlobalVariableCheck("Prot_ConteoSerie"))
      ConteoOrdenesSerie = (int)GlobalVariableGet("Prot_ConteoSerie");
   if(GlobalVariableCheck("Prot_PisoActual"))
      PisoActual = GlobalVariableGet("Prot_PisoActual");
   if(GlobalVariableCheck("Prot_UltimoEscalon"))
      UltimoEscalon = GlobalVariableGet("Prot_UltimoEscalon");
   if(GlobalVariableCheck("Prot_VolRef"))
      Vol_Ref = GlobalVariableGet("Prot_VolRef");
   if(GlobalVariableCheck("Prot_N_Principal"))
      N_Principal = (int)GlobalVariableGet("Prot_N_Principal");
   if(GlobalVariableCheck("Prot_VolTP"))
      Vol_Total_Paragua = GlobalVariableGet("Prot_VolTP");
   if(GlobalVariableCheck("Prot_MaxLoss"))
      MaxHistoricLoss = GlobalVariableGet("Prot_MaxLoss");
   if(GlobalVariableCheck("Prot_Recovery"))
      RecoveryCount = (int)GlobalVariableGet("Prot_Recovery");
   if(GlobalVariableCheck("Prot_Bloqueo11"))
      Bloqueo_11_Plus = (GlobalVariableGet("Prot_Bloqueo11") > 0.5);
}

//+------------------------------------------------------------------+
//| Normalizar símbolo para comparaciones robustas                  |
//+------------------------------------------------------------------+
string NormalizeSymbol(string symbol)
{
   string s = symbol;
   StringToUpper(s);
   
   // Si el nombre contiene XAU o GOLD, es oro.
   if(StringFind(s, "XAU", 0) >= 0 || StringFind(s, "GOLD", 0) >= 0) 
   {
      return "XAU_FOUND"; 
   }
   return s;
}

//+------------------------------------------------------------------+
//| Función para obtener el símbolo correcto de trading (XAUUSDp)    |
//| Esta función busca en el Market Watch el símbolo de Oro          |
//+------------------------------------------------------------------+
string GetTradingSymbol()
{
   string possibleSymbols[] = {"XAUUSDp", "XAUUSD", "XAUUSD.", "GOLD", "XAUUSDm"};
   
   for(int i = 0; i < ArraySize(possibleSymbols); i++)
   {
      if(SymbolSelect(possibleSymbols[i], true)) 
      {
         Print("PARAGUA: Protegiendo símbolo: ", possibleSymbols[i]);
         return possibleSymbols[i];
      }
   }

   Print("Advertencia: Usando símbolo por defecto XAUUSDp");
   return "XAUUSDp";
}

//+------------------------------------------------------------------+
//| Función para forzar el refresco de precios de XAUUSD             |
//| Esto resuelve el problema de precios desactualizados             |
//| cuando el Paragua está en otro gráfico                           |
//+------------------------------------------------------------------+
bool RefreshXAUUSDPrice()
{
   // Validación universal sin importar el nombre del símbolo
   if(TradingSymbol == "" || !SymbolSelect(TradingSymbol, true))
   {
      Print("[XAUUSD] Error: Símbolo de trading no disponible: ", TradingSymbol);
      return false;
   }
   
   // Forzar actualización de cotizaciones
   RefreshRates();
   
   // Verificar que los precios sean válidos
   double bid = MarketInfo(TradingSymbol, MODE_BID);
   double ask = MarketInfo(TradingSymbol, MODE_ASK);
   
   if(bid <= 0 || ask <= 0)
   {
      Print("[XAUUSD] Error: Precios inválidos para ", TradingSymbol, " Bid=", bid, " Ask=", ask);
      return false;
   }
   
   // Log de depuración (solo cada 10 ticks para no saturar)
   if(Counter % 10 == 0)
   {
      Print("[XAUUSD] Precio refrescado: Bid=", bid, " Ask=", ask);
   }
   
   UltimaActualizacionPrecio = TimeCurrent();
   return true;
}

//+------------------------------------------------------------------+
//| DetectarDireccionEAPrincipal                                     |
//+------------------------------------------------------------------+
bool DetectarDireccionEAPrincipal()
{
   if(DireccionDetectada)
   {
      Print("Direccion ya detectada - No redetectar");
      return (DireccionEAPrincipal == OP_BUY || DireccionEAPrincipal == OP_SELL);
   }

   int buysPrincipal = 0;
   int sellsPrincipal = 0;
   if(TradingSymbol == "") return false;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            
            if(OrderType() == OP_BUY) 
               buysPrincipal++;
            else if(OrderType() == OP_SELL) 
               sellsPrincipal++;
         }
      }
   }
   
   if(buysPrincipal > 0 && sellsPrincipal == 0)
   {
      DireccionEAPrincipal = OP_BUY;
      DireccionDetectada = true;
      TiempoDeteccion = TimeCurrent();
      Print("Direccion detectada: BUY (" + IntegerToString(buysPrincipal) + " posiciones) - " + TimeToString(TiempoDeteccion));
      return true;
   }
   else if(sellsPrincipal > 0 && buysPrincipal == 0)
   {
      DireccionEAPrincipal = OP_SELL;
      DireccionDetectada = true;
      TiempoDeteccion = TimeCurrent();
      Print("Direccion detectada: SELL (" + IntegerToString(sellsPrincipal) + " posiciones) - " + TimeToString(TiempoDeteccion));
      return true;
   }
   else if(buysPrincipal > 0 && sellsPrincipal > 0)
   {
      Print("ERROR: EA principal tiene operaciones mezcladas");
      return false;
   }
   else
   {
      Print("No se detectaron operaciones del EA principal");
      return false;
   }
}

//+------------------------------------------------------------------+
//| DebeResetearDeteccion                                            |
//+------------------------------------------------------------------+
bool DebeResetearDeteccion()
{
   if(TradingSymbol == "") return true;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS)) {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol))
         {
            if(OrderMagicNumber() == Magic_Number) continue;
            if(StringFind(OrderComment(), "Cobertura", 0) >= 0) continue;
            return false;
         }
      }
   }
   return true;
}

void GestionarResetDeteccion()
{
   if(DireccionDetectada && DebeResetearDeteccion())
   {
      DireccionDetectada = false;
      DireccionEAPrincipal = -1;
      Print("Reset deteccion - EA principal sin posiciones");
   }
}

// Llamar esta función en OnTick() y OnTimer()

// NUEVA FUNCIÓN: Lote Proporcional para equilibrio 1:1
double CalcularLoteProporcional()
{
   double lotePrincipal = GetPrincipalTotalLot();
   double loteParaguaActual = GetParaguaTotalLot();
   
   // Si no hay nada abierto, empezamos con el mínimo
   if(lotePrincipal <= 0) return LoteMinimo;
   
   // La meta es que LotePrincipal - LoteParagua = 0
   double faltante = lotePrincipal - loteParaguaActual;
   
   // Si ya estamos cubiertos o sobrepasados, no abrir más
   if(faltante <= 0) return 0;
   
   // Limitamos el lote al máximo permitido por tus inputs
   double loteFinal = MathMin(faltante, LoteMaximo);
   return NormalizeDouble(MathMax(loteFinal, LoteMinimo), 2);
}

//+------------------------------------------------------------------+
//| Ajustar lote por margen disponible                               |
//+------------------------------------------------------------------+
double AjustarLotePorMargen(double lote)
{
   // Usar TradingSymbol (variable global ya asignada)
   if(TradingSymbol == "") return lote;
   
   double margenLibre = AccountFreeMargin();
   double margenRequerido = MarketInfo(TradingSymbol, MODE_MARGINREQUIRED);
   
   if(margenRequerido <= 0) return lote;
   
   double loteMaximoPorMargen = margenLibre / margenRequerido;
   double loteAjustado = MathMin(lote, loteMaximoPorMargen);
   loteAjustado = MathMax(loteAjustado, LoteMinimo);
   
   if(loteAjustado < lote)
   {
      Print(StringFormat("Lote ajustado por margen: %.3f -> %.3f", lote, loteAjustado));
   }
   
   return NormalizeDouble(loteAjustado, 2);
}

//+------------------------------------------------------------------+
//| Cerrar gráficos XAUUSD con espera activa (hasta 35 segundos)     |
//+------------------------------------------------------------------+
bool CerrarGraficoXAUUSDConReintentos()
{
   datetime inicio = TimeCurrent();
   int maxSegundos = 35;
   long targetId = -1;
   
   // FASE 1: Esperar activamente a que el gráfico sea detectable
   Print("[PARAGUA] Buscando grafico XAUUSDp...");
   while(TimeCurrent() - inicio < maxSegundos && targetId < 0)
   {
      long chartId = ChartFirst();
      while(chartId >= 0 && targetId < 0)
      {
         string symbol = ChartSymbol(chartId);
         string upperSymbol = symbol;
         StringToUpper(upperSymbol);
         
         if(StringFind(upperSymbol, "XAU", 0) >= 0 && symbol != "" && chartId != ChartID())
         {
            targetId = chartId;
            Print("[PARAGUA] Grafico XAUUSDp detectado. ID=", targetId, " Simbolo=", symbol);
         }
         chartId = ChartNext(chartId);
      }
      
      if(targetId < 0)
      {
         Sleep(1000);
         Print("[PARAGUA] Esperando deteccion... ", TimeCurrent() - inicio, "s");
      }
   }
   
   if(targetId < 0)
   {
      Print("[PARAGUA] ERROR: No se detecto grafico XAUUSDp despues de ", maxSegundos, " segundos.");
      return false;
   }
   
   // FASE 2: Intentar cerrar el gráfico
   Print("[PARAGUA] Intentando cerrar grafico ID=", targetId);
   if(ChartClose(targetId))
   {
      Print("[PARAGUA] EXITO: Grafico XAUUSDp cerrado correctamente.");
      return true;
   }
   else
   {
      int error = GetLastError();
      Print("[PARAGUA] ERROR: No se pudo cerrar el grafico. Error=", error);
      return false;
   }
}

//+------------------------------------------------------------------+
//| ClosePartialLot                                                  |
//+------------------------------------------------------------------+
bool ClosePartialLot(int type, double lotToClose)
{
    double lotRemaining = lotToClose;
    bool success = false;
    if(TradingSymbol == "") return false;
    
    for(int i = OrdersTotal()-1; i >= 0; i--)
    {
        if(lotRemaining <= 0) break;
        
        if(OrderSelect(i, SELECT_BY_POS)) 
        {
            if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol) && OrderType() == type)
            {
                double lot = OrderLots();
                double closeLot = MathMin(lot, lotRemaining);
                
                bool isParagua = (OrderMagicNumber() == Magic_Number);
                
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
   
   // --- CORRECCIÓN: Forzar refresco de precios del Oro antes del primer intento ---
   if(!RefreshXAUUSDPrice())
   {
      Print("Error: No se pudo refrescar precio de ", TradingSymbol, ". Reintentando...");
      return false;
   }
   
   // --- AHORA los precios están actualizados ---
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
   
   // Ajustar lote por margen usando el símbolo correcto
   double loteAjustado = AjustarLotePorMargen(LoteFijo);
   
   if(loteAjustado < LoteMinimo)
   {
      Print("Error: Lote ajustado es menor al mínimo permitido para " + TradingSymbol);
      return false;
   }
   
   int erroresRecuperables[] = {10004, 10006, 10007, 10008, 147};
   datetime tiempoInicio = TimeCurrent();
   int timeoutMaximo = 40;
   
   for(int intento = 0; intento < MaxReintentosOrden; intento++)
   {
      if(TimeCurrent() - tiempoInicio >= timeoutMaximo)
      {
         Print("TIMEOUT: No se pudo abrir cobertura en " + TradingSymbol);
         return false;
      }
      
      GetLastError(); 
      
      // --- CORRECCIÓN: Usar TradingSymbol (variable global) ---
      Print("Intentando abrir cobertura en ", TradingSymbol, " | Lote: ", loteAjustado, " | Precio: ", precio);
      int ticket = OrderSend(TradingSymbol, tipoOrden, loteAjustado, precio, 3, 0, 0, 
                             "Cobertura Protector", Magic_Number, 0, clrGreen);
      
      if(ticket > 0)
      {
         Print("Cobertura abierta en " + TradingSymbol + " (ticket: " + IntegerToString(ticket) + ")");
         return true;
      }
      else
      {
         int error = GetLastError();
         bool esRecuperable = false;
         for(int i = 0; i < ArraySize(erroresRecuperables); i++)
            if(error == erroresRecuperables[i]) { esRecuperable = true; break; }
         
         if(!esRecuperable)
         {
            Print("Error FATAL en " + TradingSymbol + ": " + IntegerToString(error));
            return false;
         }
         
         Sleep(200 * (intento + 1));
         
         // --- CORRECCIÓN: Forzar refresco ANTES DE CADA REINTENTO ---
         // Esto garantiza que cada reintento tenga un precio fresco,
         // resolviendo el problema de Requote (error 10004)
         if(!RefreshXAUUSDPrice())
         {
            Print("Error: No se pudo refrescar precio en reintento ", intento + 1);
            // Continuar con el reintento aunque el refresco falle (usar precio anterior)
         }
         
         // Actualizar precio Bid/Ask del Oro antes del reintento
         if(DireccionEAPrincipal == OP_BUY)
            precio = MarketInfo(TradingSymbol, MODE_BID);
         else
            precio = MarketInfo(TradingSymbol, MODE_ASK);
      }
   }
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
    // Usar TradingSymbol (variable global ya asignada)
    if(TradingSymbol == "") return 0;
    
    double bid = MarketInfo(TradingSymbol, MODE_BID);
    double ask = MarketInfo(TradingSymbol, MODE_ASK);
    double point = MarketInfo(TradingSymbol, MODE_POINT);
    
    if(bid <= 0 || ask <= 0 || point <= 0) {
        return 0;
    }
    
    double spread = (ask - bid) / point;
    int digits = (int)MarketInfo(TradingSymbol, MODE_DIGITS);
    
    // Ajuste para brokers de 3 o 5 dígitos (Pips vs Points)
    if(digits == 3 || digits == 5) {
        spread /= 10;
    }
    
    return spread;
}

//+------------------------------------------------------------------+
//| Determinar niveles de referencia (CORREGIDA PARA OTROS GRÁFICOS) |
//+------------------------------------------------------------------+
bool DeterminarNivelesReferencia()
{
   static double ultimoMaximoProfit = -999999.0;
   static datetime tiempoInicioAgotamiento = 0;
   
   // Calculamos el profit actual del Paragua (la serie ganadora en caída)
   double profitActualParagua = GetParaguaTotalProfit(); // Incluye swaps/comisiones

   // LÓGICA DE AGOTAMIENTO (30 SEGUNDOS)
   if(profitActualParagua > ultimoMaximoProfit) 
   {
      // El beneficio sigue aumentando: el mercado se mueve, reseteamos reloj
      ultimoMaximoProfit = profitActualParagua;
      tiempoInicioAgotamiento = TimeCurrent();
      Agotamiento_Confirmado = false;
   }
   else 
   {
      // El beneficio se estancó o retrocedió: comprobamos estabilidad
      if(TimeCurrent() - tiempoInicioAgotamiento >= 30) 
      {
         Agotamiento_Confirmado = true;
      }
      else 
      {
         Agotamiento_Confirmado = false;
      }
   }

   // GESTIÓN DE ESCALONES DE EQUITY (Para apertura de Series A, B, C)
   double equityActual = AccountEquity();
   double balanceActual = AccountBalance();
   double ratioActual = (balanceActual > 0) ? (equityActual / balanceActual) * 100.0 : 100.0;

   // Si la equity cae por debajo del último escalón registrado, actualizamos para la siguiente apertura
   if(ratioActual < (UltimoEscalon - 1.0)) 
   {
      UltimoEscalon = ratioActual;
      // El reseteo de series ocurriría en la lógica de Vigilia, no aquí.
   }

   return Agotamiento_Confirmado;
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
   int spacing = 53; // Espaciado ligeramente reducido para optimizar espacio
   
   long chartId = ChartFirst();
   while(chartId >= 0) {
      // 1. Fondo del panel
      ObjectCreate(chartId, "PanelBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XDISTANCE, x - 10);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YDISTANCE, y - 5);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_XSIZE, 900);
      ObjectSetInteger(chartId, "PanelBG", OBJPROP_YSIZE, 500); // Aumentado para nueva línea 
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
//| Actualizar panel de monitoreo con cambios visuales               |
//| Incluye: Vigilia, Espera, Proteccion, Friday Logout, Precaución  |
//+------------------------------------------------------------------+
void UpdateMonitoringPanel(double equityPercent, double spread, long chartId)
{
   // 1. Calculo de ganancia/perdida de la cuenta
   double diferenciaPercent = equityPercent - 100.0;
   string lossGainText;
   color lossGainColor;

   if(diferenciaPercent >= 0)
   {
      lossGainText = StringFormat("Ganancia: %.2f%%", diferenciaPercent);
      lossGainColor = clrDodgerBlue; // Azul vivo (o clrBlue para azul estándar)
   }
   else
   {
      lossGainText = StringFormat("Perdida: %.2f%%", MathAbs(diferenciaPercent));
      lossGainColor = COLOR_LOSS;
   }

   // 2. Actualizacion de etiquetas estandar
   UpdateChartLabel(chartId, "LblPositions", "Posiciones: " + IntegerToString(CurrentPrincipalPositions) + " | Max: " + IntegerToString(MaxHistoricPositions));
   UpdateChartLabel(chartId, "LblLoss", lossGainText, lossGainColor);
   UpdateChartLabel(chartId, "LblMaxLoss", "Perdida Max Hist: " + DoubleToString(MaxHistoricLoss, 2) + "%");
   UpdateChartLabel(chartId, "LblSpread", "Spread: " + DoubleToString(spread, 1));
   UpdateChartLabel(chartId, "LblMaxSpread", "Max Spread: " + DoubleToString(MaxHistoricSpread, 1));
   UpdateChartLabel(chartId, "LblRecoveries", "Recuperaciones: " + IntegerToString(RecoveryCount));

   // 3. Distancia entre extremos
   UpdateChartLabel(chartId, "LblPeorEscenario", StringFormat("Distancia Ext: %.2f%%", DistanciaExtremosActual), COLOR_SPREAD);
   UpdateChartLabel(chartId, "LblMaxDistancia", StringFormat("Max Distancia: %.2f%%", MaxDistanciaHistorica), COLOR_MAX_VALUES);

   // 4. Logica de estado del sistema (jerarquia de seguridad)
   string estadoText;
   color estadoColor;

   // ESTADO PRIORIDAD 1: Modo Precaución (nuevo)
   if(ModoPrecaucionActivado)
   {
      double perdidaActual = 100.0 - equityPercent;
      if(perdidaActual < 0) perdidaActual = 0;
      estadoText = "PRECAUCION: " + DoubleToString(perdidaActual, 1) + "%";
      estadoColor = clrOrange;
   }
   // ESTADO PRIORIDAD 2: Modo Proteccion Activo
   else if(ModoProteccionActivado)
   {
      double pisoLoss = 100.0 - PisoActual;
      estadoText = "PROTECCION ACTIVO: " + DoubleToString(pisoLoss, 2) + "%";
      estadoColor = clrRed;
   }
   // ESTADO PRIORIDAD 3: Friday Logout
   else if(FridayLogout && EsViernesNoche())
   {
      int totalPos = CurrentPrincipalPositions + CountParaguaPositions();

      if(totalPos > 0)
      {
         estadoText = "FRIDAY: ESPERANDO CIERRE (" + IntegerToString(totalPos) + ")";
         estadoColor = clrOrange;
      }
      else
      {
         estadoText = "FRIDAY: EJECUTANDO SALIDA";
         estadoColor = clrSalmon;

         if(!GraficoCerrado)
         {
            Print("Friday Logout: Posiciones en cero. Cerrando graficos.");
            CerrarGraficoXAUUSDConReintentos();
            GraficoCerrado = true;
         }
      }
   }
   // ESTADO PRIORIDAD 4: Espera de activacion (temporizador)
   else if(InWaitingState)
   {
      int segRestantes = MinDuration * 60 - (int)(TimeCurrent() - TimerStart);
      if(segRestantes < 0) segRestantes = 0;
      estadoText = "ESPERA: " + IntegerToString(segRestantes) + "s";
      estadoColor = clrYellow;
   }
   // ESTADO PRIORIDAD 5: Vigilancia normal
   else
   {
      double lossThreshold = 100.0 - EquityThreshold;
      estadoText = "VIGILANCIA: " + DoubleToString(lossThreshold, 2) + "%";
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
   
   // VERIFICACIÓN MÁS ROBUSTA
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
   
   // --- LÓGICA DE RECUPERACIONES (COMO EN 78PARAGUA) ---
   if(equityPercent <= EquityThreshold) {
      WasBelowThreshold = true;
   } 
   else if(WasBelowThreshold && equityPercent > (EquityThreshold + 2.0)) // +2% de margen para confirmar
   {
      RecoveryCount++;
      GlobalVariableSet("Prot_Recovery", (double)RecoveryCount);
      WasBelowThreshold = false;
      Print("Recuperación detectada. Total: ", RecoveryCount);
   }

   // Actualizar conteo de posiciones
   CurrentPrincipalPositions = CountPrincipalPositions();
   if(CurrentPrincipalPositions > MaxHistoricPositions) {
      MaxHistoricPositions = CurrentPrincipalPositions;
      GlobalVariableSet("Protector_MaxPositions", (double)MaxHistoricPositions);
   }
      
   if(lossPercent > MaxHistoricLoss) {
      MaxHistoricLoss = lossPercent; 
      GlobalVariableSet("Protector_MaxLoss", MaxHistoricLoss);
   }
      
   if(spread > MaxHistoricSpread) {
      MaxHistoricSpread = spread;
      GlobalVariableSet("Protector_MaxSpread", MaxHistoricSpread);
   }

   // IMPORTANTE: Llamar a la distancia aquí
   CalcularDistanciaOperativa();
}

//+------------------------------------------------------------------+
//| Función EsViernesNoche                                           |
//| Determina la ventana estricta de cierre con validación local     |
//+------------------------------------------------------------------+
bool EsViernesNoche()
{
   MqlDateTime dt_server;
   TimeToStruct(TimeCurrent(), dt_server); // Hora del servidor
   
   if(dt_server.day_of_week == 5) // Viernes
   {
      if(dt_server.hour >= LogoutHour) 
      {
         return true;
      }
   }
   return false;
}

// Función que cierra solo órdenes del Principal
void CerrarSoloPrincipalEnProfit()
{
   if(TradingSymbol == "") return;
   
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         if(NormalizeSymbol(OrderSymbol()) == NormalizeSymbol(TradingSymbol) && OrderMagicNumber() != Magic_Number)
         {
            double neto = OrderProfit() + OrderCommission() + OrderSwap();
            if(neto > 0)
            {
               if(OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3))
               {
                  Print("Orden Principal cerrada en Profit: Ticket ", OrderTicket());
               }
            }
         }
      }
   }
}

// Función que equilibra la balanza
void EquilibrarBalanza()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number)
      {
         double neto = OrderProfit() + OrderCommission() + OrderSwap();
         if(neto > 0)
         {
            if(OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3))
            {
               Print("Balanza equilibrada: Orden Paragua cerrada.");
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CalcularLotePorUnidad                                            |
//+------------------------------------------------------------------+
double CalcularLotePorUnidad()
{
   // Usar TradingSymbol (variable global ya asignada)
   if(TradingSymbol == "") return LoteMinimo;
   
   double totalLotesPrincipal = GetPrincipalTotalLot();
   double minLot = MarketInfo(TradingSymbol, MODE_MINLOT);
   if(minLot <= 0) minLot = LoteMinimo;
   
   if(totalLotesPrincipal <= 0) return minLot;
   
   // Dividimos el total del principal en 10 partes iguales
   double loteBase = NormalizeDouble(totalLotesPrincipal / 10.0, 2);
   if(loteBase < minLot) loteBase = minLot;
   
   return loteBase;
}

double CalcularLoteEstructurado() {
   double balance = AccountBalance();
   double equity = AccountEquity();
   
   // Fórmula: Lote Base + (Influencia por Posiciones Abiertas) + (Influencia por Equity)
   double loteCalculado = LoteMinimo + (CurrentOpenPositions * FactorPosiciones) + ((balance - equity) * FactorEquity);
   
   // Normalizar para que no exceda el máximo ni sea menor al mínimo
   if(loteCalculado > LoteMaximo) loteCalculado = LoteMaximo;
   if(loteCalculado < LoteMinimo) loteCalculado = LoteMinimo;
   
   return NormalizeDouble(loteCalculado, 2);
}

// ================================================================
// 2. FUNCIÓN QUE VIGILA EL AGOTAMIENTO
// ================================================================
void RevisarLogicaAgotamiento() {
   // Solo actuamos si el sistema detectó una señal de agotamiento previa
   if(Agotamiento_Activo) {
      
      long segundosTranscurridos = TimeCurrent() - Timer_Gatillo;
      
      // Si el tiempo transcurrido superó el límite (ej. 30 segundos)
      if(segundosTranscurridos >= SegundosAgotamiento) {
         Print("Agotamiento confirmado después de ", segundosTranscurridos, " segundos.");
         
         // LLAMAMOS AL BOTÓN DE CIERRE
         CerrarTodoElSistema();
         
         // Limpiamos las variables para el siguiente ciclo
         Agotamiento_Activo = false;
         Timer_Gatillo = 0;
      }
   }
}

// ================================================================
// FUNCIÓN ONTIMER COMPLETA (EL MOTOR)
// ================================================================
// --- REEMPLAZA TU ONTIMER ACTUAL POR ESTE ---
void OnTimer()
{
   // 1. Reset de seguridad para el fin de semana usando TimeLocal (Punto 5)
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   if((dt.day_of_week == 0 || dt.day_of_week == 1) && !ModoProteccionActivado)
   {
      if(GraficoCerrado) 
      {
         GraficoCerrado = false;
         Print("Mantenimiento: Monitoreo reactivado (Reset VPS/Lunes).");
      }
   }

   // 2. Si ya se cerró el viernes, y NO es lunes ni domingo, no procesar nada
   if(EsViernesNoche() && GraficoCerrado) return;

   // 3. Actualizar conteos
   CurrentOpenPositions = CountParaguaPositions(); 
   CurrentPrincipalPositions = CountPrincipalPositions();
   int totalPos = CurrentPrincipalPositions + CurrentOpenPositions;
   
   // 4. REGLA DE ORO DEL VIERNES: Cierre por horario
   if(FridayLogout && EsViernesNoche())
   {
      // NO importa la volatilidad. Si totalPos es 0, cerramos.
      if(totalPos == 0)
      {
         Print("Viernes + Horario alcanzado + Cuenta en cero. Cerrando gráficos...");
         CerrarGraficoXAUUSDConReintentos(); 
         GraficoCerrado = true;
         return; 
      }
      else 
      {
         // Si hay órdenes, NO cerramos el gráfico, nos quedamos a proteger
         // Pero avisamos en el panel (esto ya lo hace UpdateAllChartsPanels)
      }
   }
   
   // 5. Monitoreo visual y protección de Equity
   double eqPercent = (AccountBalance() > 0) ? (AccountEquity() / AccountBalance()) * 100.0 : 100.0;
   
   // Si no estamos en modo protección, vigilamos la activación
   if(!ModoProteccionActivado)
      CheckActivationConditions(eqPercent);
   else
      ManageProtectionMode(eqPercent);

   UpdateAllChartsPanels(eqPercent, GetSpreadForXAUUSD());
}

//+------------------------------------------------------------------+
//| 3. GESTIÓN DE ESCALONAMIENTO (Series A, B y C)                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Calcular Lote Dinámico (Punto 2)                                 |
//+------------------------------------------------------------------+
double CalcularLoteDinamico(int ordenActualSerie)
{
   // Usar TradingSymbol (variable global ya asignada)
   if(TradingSymbol == "") return LoteMinimo;
   
   double lotePrincipal = GetPrincipalTotalLot();
   double loteStep = MarketInfo(TradingSymbol, MODE_LOTSTEP);
   if(loteStep <= 0) loteStep = 0.01;
   
   if(lotePrincipal <= 0) return LoteMinimo;
   
   double lotBase = MathFloor((lotePrincipal / 10.0) / loteStep) * loteStep;
   if(lotBase < loteStep) lotBase = loteStep;
   
   double totalAsignado = lotBase * 10;
   double remainder = lotePrincipal - totalAsignado;
   double lotePosicion = lotBase;
   
   if(ordenActualSerie > 10) {
      ordenActualSerie = 10;
   }
   
   if(remainder > 0) {
      int numStepsSobrantes = (int)MathRound(remainder / loteStep);
      if(ordenActualSerie <= numStepsSobrantes) {
         lotePosicion += loteStep;
      }
   }
   
   return NormalizeDouble(MathMax(lotePosicion, LoteMinimo), 2);
}

void ManageProtectionMode(double equityPercent)
{
   int actuales = CountParaguaPositions();
   double distanciaRequerida = 1.0; 

   // Definición de Series y Pausas (Punto 2)
   if(ConteoOrdenesSerie == 4) distanciaRequerida = 5.0;       // Pausa 1
   else if(ConteoOrdenesSerie == 7) distanciaRequerida = 10.0; // Pausa 2
   else if(ConteoOrdenesSerie > 7) distanciaRequerida = 1.0;  // Serie C

   if(equityPercent <= (UltimoEscalon - distanciaRequerida))
   {
      bool autorizar = (actuales < 10); // Serie Base abre por Equity

      // Filtro de Candado y Agotamiento para Posición 11+
      if(actuales >= 10 && !Bloqueo_11_Plus) {
         double volActual = GetPrincipalTotalLot();
         if(ValidarCandadoParagua() && volActual >= (Vol_Ref - 0.001)) {
             autorizar = true;
         }
      }

      if(autorizar) {
         LoteFijo = CalcularLoteDinamico(ConteoOrdenesSerie + 1);
         if(AbrirCoberturaConReintentos()) {
            UltimoEscalon = equityPercent; 
            ConteoOrdenesSerie++; 
            if(ConteoOrdenesSerie == 10) {
               Vol_Total_Paragua = GetParaguaTotalLot();
            }
            SavePersistentData();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 5. MOTOR DE LA BALANZA (Regla Estricta del 35%)                  |
//+------------------------------------------------------------------+
void EjecutarCierreEstructurado()
{
   // 1. FILTRO DE AGOTAMIENTO (30s de estabilidad)
   if(!Agotamiento_Confirmado) return;

   // 2. CÁLCULO DE COMBO (Profit Neto Total de todo lo que sea ORO)
   double profitCombo = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS) && NormalizeSymbol(OrderSymbol()) == "XAU_FOUND") {
         profitCombo += (OrderProfit() + OrderSwap() + OrderCommission());
      }
   }

   // 3. REGLA DE ORO: Si el total es positivo, cerramos TODO y reseteamos
   if(profitCombo > 0.10) { // Un pequeño margen de 10 centavos para cubrir deslizamientos
      Print("COMBO POSITIVO: Liquidando sistema completo.");
      CerrarTodoElSistema();
      return;
   }

   // 4. LÓGICA DE BALANZA (Si el combo es negativo)
   double volRef = GlobalVariableGet("Prot_VolRef");
   double volTotalParagua = GlobalVariableGet("Prot_VolTP");
   if(volRef <= 0) return;
   
   if(volTotalParagua <= 0) volTotalParagua = volRef; // Fallback real si no llegó a 10

   double volActualPrincipal = GetPrincipalTotalLot();
   double volActualParagua = GetParaguaTotalLot();
   int unidadesParaguaActuales = CountParaguaPositions();

   // % de progreso de cierre
   double porcPrincipalCerrado = (1.0 - (volActualPrincipal / volRef)) * 100.0;
   if(porcPrincipalCerrado < 0) porcPrincipalCerrado = 0;
   
   double lotesCerradosParagua = volTotalParagua - volActualParagua;
   double porcParaguaCerrado = (lotesCerradosParagua / volTotalParagua) * 100.0;
   if(porcParaguaCerrado < 0) porcParaguaCerrado = 0;

   // --- PRIORIDAD 1: CERRAR PRINCIPAL (Reducir el riesgo) ---
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() != Magic_Number) {
         if(NormalizeSymbol(OrderSymbol()) == "XAU_FOUND") {
            double neto = OrderProfit() + OrderSwap() + OrderCommission();
            
            if(neto > 0) {
               double nuevoVolPrincipal = volActualPrincipal - OrderLots();
               double nuevoPorcPrincipal = (1.0 - (nuevoVolPrincipal / volRef)) * 100.0;
               double brechaSimulada = MathAbs(nuevoPorcPrincipal - porcParaguaCerrado);

               if(brechaSimulada <= 35.0) {
                  Print("Balanza: Cerrando Principal. Brecha: ", DoubleToString(brechaSimulada, 1), "%");
                  if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3))
                     Print("Error cerrando Principal: ", GetLastError());
                  return; 
               }
            }
         }
      }
   }

   // --- PRIORIDAD 2: CERRAR PARAGUA (Liberar margen) ---
   if(unidadesParaguaActuales > 0) {
      int ticketBest = -1;
      double maxProfit = -9999;
      
      for(int i = OrdersTotal()-1; i >= 0; i--) {
         if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number) {
            double neto = OrderProfit() + OrderSwap() + OrderCommission();
            if(neto > maxProfit) {
               maxProfit = neto;
               ticketBest = OrderTicket();
            }
         }
      }

      if(ticketBest > 0 && maxProfit > 0) {
         if(OrderSelect(ticketBest, SELECT_BY_TICKET)) {
            double nuevoVolParagua = volActualParagua - OrderLots();
            double nuevoPorcParagua = (1.0 - (nuevoVolParagua / volTotalParagua)) * 100.0;
            double brechaSimulada = MathAbs(porcPrincipalCerrado - nuevoPorcParagua);

            if(brechaSimulada <= 35.0) {
               Print("Balanza: Paragua Liberador. Brecha: ", DoubleToString(brechaSimulada, 1), "%");
               if(!OrderClose(ticketBest, OrderLots(), OrderClosePrice(), 3))
                  Print("Error cerrando Paragua: ", GetLastError());
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| FUNCIÓN AUXILIAR: CIERRE TOTAL                                   |
//+------------------------------------------------------------------+
void CerrarTodoElSistema()
{
   Print("Iniciando cierre total del sistema...");
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS)) {
         // Cerramos todo lo que sea Oro (Principal y Paragua)
         if(NormalizeSymbol(OrderSymbol()) == "XAU_FOUND") {
            if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 10, clrWhite)) {
               Print("Fallo al cerrar ticket ", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
   DesactivarModoProteccion();
   ResetearEpisodio(); // Aseguramos limpieza de variables
}

//+------------------------------------------------------------------+
//| FUNCIONES AUXILIARES DE SOPORTE                                  |
//+------------------------------------------------------------------+

bool ValidarCandadoParagua()
{
   // Solo permite posición N+1 si todas las anteriores están en Profit (Punto 3)
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number)
      {
         if((OrderProfit() + OrderCommission() + OrderSwap()) <= 0) return false;
      }
   }
   return true;
}

bool ValidarBalanza(double proximoProgresoCerradoParagua)
{
   double volRef = GlobalVariableGet("Prot_VolRef");
   if(volRef <= 0) return false;

   // % de progreso de cierre del principal
   double principalCerrado = (1.0 - (GetPrincipalTotalLot() / volRef)) * 100.0;
   if(principalCerrado < 0) principalCerrado = 0;
   
   // % de progreso del paragua (viene inyectado como param ya calculado por volumen)
   // Cálculo de la brecha resultante
   double brecha = MathAbs(principalCerrado - proximoProgresoCerradoParagua);
   
   return (brecha <= 35.0);
}

bool CerrarUnidadParaguaConGanancia()
{
   // Busca la orden del Paragua más rentable para cerrar y equilibrar
   int ticketBest = -1;
   double maxProfit = -99999;

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number)
      {
         double p = OrderProfit() + OrderCommission() + OrderSwap();
         if(p > maxProfit) { maxProfit = p; ticketBest = OrderTicket(); }
      }
   }

   if(ticketBest > 0 && maxProfit > 0)
   {
      return OrderClose(ticketBest, OrderLots(), OrderClosePrice(), 3);
   }
   return false;
}

void LimpiarExcesoParagua()
{
   if(GetPrincipalTotalLot() < (Vol_Ref - 0.001)) {
      Bloqueo_11_Plus = true; 
   }

   while(CountParaguaPositions() > 10)
   {
      int ticketPeor = -1;
      double minProfit = 999999;

      for(int i = OrdersTotal()-1; i >= 0; i--) {
         if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == Magic_Number) {
            double p = OrderProfit() + OrderSwap() + OrderCommission();
            if(p < minProfit) { 
               minProfit = p; 
               ticketPeor = OrderTicket(); 
            }
         }
      }
      
      if(ticketPeor > 0) {
          if(minProfit < 0) {
             Bloqueo_11_Plus = true; // Bloqueo definitivo si la poda causó pérdida neta (o cerró en rojo)
          }
          if(!OrderClose(ticketPeor, OrderLots(), OrderClosePrice(), 3)) {
             Print("Error limpiando exceso: ", GetLastError());
             break; 
          }
          Print("Limpieza: Exceso de Paragua eliminado (Ticket ", ticketPeor, ")");
      } else {
          break; 
      }
   }
}

double GetParaguaTotalProfit()
{
   double totalProfit = 0.0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         if(OrderMagicNumber() == Magic_Number)
            totalProfit += (OrderProfit() + OrderSwap() + OrderCommission());
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Definición de CalcularLoteInicial                                |
//+------------------------------------------------------------------+
void CalcularLoteInicial()
{
   // 1. Calcular la unidad base (10% del Vol_Ref para la balanza de 10 posiciones)
   if(Vol_Ref > 0)
   {
      LoteFijo = Vol_Ref / 10.0;
      if(LoteFijo < 0.01) LoteFijo = 0.01;
      LoteFijo = NormalizeDouble(LoteFijo, 2);
   }
   else
   {
      LoteFijo = LoteMinimo;
   }

   // 3. Filtros de seguridad (no bajar del mínimo ni subir del máximo de los inputs)
   if(LoteFijo < LoteMinimo) LoteFijo = LoteMinimo;
   if(LoteFijo > LoteMaximo) LoteFijo = LoteMaximo;
   
   Print("Lote Inicial Calculado: Vol_Ref Total(", Vol_Ref, ") -> Unidad Paragua: ", LoteFijo);
}