---
name: mql5-ea-dev
description: Estándares y plantilla para desarrollar Asesores Expertos (EA) en MQL5 con enfoque cuantitativo y POO. Úsala siempre que el usuario pida crear, revisar o modificar código MQL5 (Expert Advisor, indicador, script para MetaTrader 5). Impone por defecto filtro de volumen, filtro RSI, operativa solo al cierre de vela, gestión de riesgo basada en ATR (SL/TP/break even/trailing stop, cada uno activable/desactivable) y lotaje elegible entre fijo o % de riesgo, salvo que el usuario indique lo contrario.
---

# Desarrollo de EAs en MQL5 (POO, nivel profesional)

Sigue este estándar SIEMPRE que generes código MQL5 para MetaTrader 5, salvo instrucción explícita en contra del usuario.

## Reglas de estrategia por defecto (obligatorias salvo que el usuario diga lo contrario)

1. **Confirmación de volumen**: antes de operar, el volumen (tick volume, `Volume[]` / `iVolume`) de la vela recién cerrada debe ser mayor al promedio de las 20 velas anteriores a ella (no incluye la vela evaluada). Calcular con `CopyTickVolume` o `CopyRealVolume` según el símbolo, sobre el rango `[shift+1, shift+20]`.
2. **Filtro RSI**: nunca **comprar** si el RSI (handle vía `iRSI`, período configurable, default 14) está en sobrecompra (>70), y nunca **vender** si está en sobreventa (<30) en el momento de la señal. El filtro es direccional: comprar en sobreventa o vender en sobrecompra sí está permitido. Estos niveles deben ser `input` configurables.
3. **Solo al cierre de vela**: la lógica de entrada/señal se evalúa una única vez por vela nueva, nunca en cada tick. Usar detección de nueva barra vía `iTime(_Symbol, _Period, 0)` comparado contra una variable estática/miembro, NUNCA `IsNewBar()` ad-hoc mal implementado ni time-based polling.
4. **Una sola operación abierta a la vez**: antes de evaluar o enviar una nueva entrada, verificar que no exista ya una posición abierta (`PositionSelect(_Symbol)` o, si el EA opera multi-símbolo/multi-magic, filtrar por symbol+magic). Si hay una posición abierta, no se evalúa ni envía ninguna orden nueva hasta cerrarla.
5. **Gestión de riesgo basada en ATR, nunca en puntos fijos**: todo EA expone un grupo de inputs de gestión de riesgo con stop loss, take profit, break even y trailing stop, cada uno con su propio `input bool` de activar/desactivar independiente. Todas las distancias (SL, TP, trigger/offset de break even, distancia/paso de trailing) se calculan como `multiplicador x ATR`, nunca como puntos fijos (`input int InpAtrPeriod` configurable, default 14; un `input double` de multiplicador por cada distancia). El ATR de la entrada (SL/TP al abrir) se lee de la última vela cerrada (shift 1), coherente con la regla 3; el ATR usado en break even/trailing (que corren cada tick) se lee de la vela en formación (shift 0). Break even y trailing solo mueven el SL a favor de la posición (nunca lo retroceden) y el trailing respeta un paso mínimo en ATR antes de mover el SL de nuevo.
6. **Lotaje: fijo o % de riesgo, elegible por input**: todo EA expone un `input enum` (p.ej. `ENUM_LOT_MODE { LOT_MODE_FIXED, LOT_MODE_RISK_PERCENT }`) para que el usuario elija el modo de cálculo del volumen. En modo fijo se usa `input double InpFixedLots` tal cual. En modo % de riesgo se usa `input double InpRiskPercent` sobre `AccountInfoDouble(ACCOUNT_BALANCE)`, convertido a lotes con la distancia de SL en ATR y `SYMBOL_TRADE_TICK_VALUE`/`SYMBOL_TRADE_TICK_SIZE`, y el resultado se normaliza a `SYMBOL_VOLUME_MIN`/`MAX`/`STEP`. El modo % de riesgo requiere que el stop loss (regla 5) esté activado — sin distancia de SL no hay base para calcular el riesgo; si el usuario activa % de riesgo con SL desactivado, es una configuración inválida: fallar en `OnInit` (`INIT_FAILED`) con un `Print` explicando la incompatibilidad, no asumir un valor por defecto silencioso.

## Arquitectura obligatoria

- **POO real**, no scripts procedurales sueltos. Estructura mínima de clases:
  - `CSignalFilter` o similar: encapsula volumen + RSI, expone `bool IsAllowedToTrade()`.
  - `CBarMonitor`: encapsula detección de vela nueva.
  - `CAtrProvider`: handle único de ATR (`iATR`), expone `GetValue(shift, &out)`; fuente de todas las distancias de gestión de riesgo.
  - `CRiskManager`: aplica break even y trailing stop en múltiplos de ATR sobre la posición abierta; corre en cada tick (no gated por vela nueva, a diferencia de la señal de entrada).
  - `CPositionSizer`: calcula el volumen a operar según `ENUM_LOT_MODE` (fijo o % de riesgo); expone `GetLots(double slDistance, double &lotsOut)`.
  - `CExpertAdvisor` (o nombre del EA): orquesta, contiene `OnTick`, `OnInit`, `OnDeinit`, delega en los filtros, en `CRiskManager`, en `CPositionSizer` y en `CTrade`. Calcula SL/TP de apertura como `precio ± multiplicador x ATR`.
- **`CTrade` nativo** (`#include <Trade\Trade.mqh>`) para toda ejecución de órdenes, incluyendo `PositionModify` para break even/trailing. Nunca `OrderSend` legacy MQL4-style.
- **Manejo exhaustivo de errores**: verificar `GetLastError()` / `ResultRetcode()` tras cada llamada de trading; verificar que los handles de indicadores (`iRSI`, `iATR`, etc.) sean distintos de `INVALID_HANDLE` en `OnInit`; verificar `CopyBuffer`/`CopyTickVolume` devuelvan `>0` antes de usar el array.
- **Buffers e indicadores**: crear los handles UNA sola vez en `OnInit` (nunca dentro de `OnTick`), liberar con `IndicatorRelease` en `OnDeinit`. Usar `ArraySetAsSeries(buffer, true)` sobre los arrays de `CopyBuffer`.
- **Inputs configurables**: volumen (período de promedio, default 20), RSI (período, niveles sobrecompra/sobreventa), modo de lotaje (fijo vs % de riesgo) con sus inputs asociados, magic number, slippage, período ATR, y el grupo completo de gestión de riesgo ATR (SL/TP/break even/trailing, cada uno con su toggle on/off y su multiplicador).
- **Inputs agrupados con `input group`**: todo bloque de inputs relacionado va precedido de su directiva `input group "Nombre"` (sintaxis MQL5 nativa que organiza el panel de propiedades del EA en secciones plegables), nunca inputs sueltos sin agrupar. Grupos mínimos esperados: `"General"` (magic number, slippage), `"Lotaje"` (modo, lotaje fijo, % de riesgo), `"ATR"` (período), `"Stop Loss / Take Profit"`, `"Break Even"`, `"Trailing Stop"`, `"Filtro de Volumen"`, `"Filtro RSI"`, y uno propio para los parámetros de la señal específica de la estrategia (p.ej. `"Cruce de Medias"`).
- **Comentarios descriptivos** en español, explicando el "por qué" de cada bloque no trivial (igual que en cualquier otro código del usuario) — no comentarios obvios.
- **Modularidad**: separar en archivos `.mqh` cuando el EA crezca (filtros, gestión de riesgo, trade manager), e incluirlos desde el `.mq5` principal.

## Plantilla de referencia

Usa `references/ea_template.mq5` como esqueleto base: incluye `CBarMonitor`, `CSignalFilter` (volumen + RSI), `CAtrProvider`, `CRiskManager` (break even + trailing en ATR), `CPositionSizer` (lotaje fijo o % de riesgo) y `CExpertAdvisor` con `CTrade`, manejo de errores, las 6 reglas por defecto y el grupo de inputs de gestión de riesgo ATR ya implementados. Adapta la señal de entrada (`CSignalFilter::GetDirection`) a la estrategia específica que pida el usuario — el filtro de volumen/RSI/cierre-de-vela, la gestión de riesgo ATR y el cálculo de lotaje se mantienen como capas obligatorias, no como la señal misma.

## Al desviarse de las reglas por defecto

Si el usuario pide explícitamente omitir volumen, RSI, operar en cada tick, usar puntos fijos en vez de ATR para el riesgo, o eliminar el modo % de riesgo (dejando solo lotaje fijo), respétalo — pero dilo explícitamente en un comentario en el código y, si es ambiguo si quiere desactivar una sola regla o varias, pregunta antes de asumir.
