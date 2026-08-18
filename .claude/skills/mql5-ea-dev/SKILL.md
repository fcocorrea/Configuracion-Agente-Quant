---
name: mql5-ea-dev
description: Estándares y plantilla para desarrollar Asesores Expertos (EA) en MQL5 con enfoque cuantitativo y POO. Úsala siempre que el usuario pida crear, revisar o modificar código MQL5 (Expert Advisor, indicador, script para MetaTrader 5). Impone por defecto filtro de volumen, filtro RSI y operativa solo al cierre de vela, salvo que el usuario indique lo contrario.
---

# Desarrollo de EAs en MQL5 (POO, nivel profesional)

Sigue este estándar SIEMPRE que generes código MQL5 para MetaTrader 5, salvo instrucción explícita en contra del usuario.

## Reglas de estrategia por defecto (obligatorias salvo que el usuario diga lo contrario)

1. **Confirmación de volumen**: antes de operar, el volumen (tick volume, `Volume[]` / `iVolume`) de la vela recién cerrada debe ser mayor al promedio de las 20 velas anteriores a ella (no incluye la vela evaluada). Calcular con `CopyTickVolume` o `CopyRealVolume` según el símbolo, sobre el rango `[shift+1, shift+20]`.
2. **Filtro RSI**: nunca **comprar** si el RSI (handle vía `iRSI`, período configurable, default 14) está en sobrecompra (>70), y nunca **vender** si está en sobreventa (<30) en el momento de la señal. El filtro es direccional: comprar en sobreventa o vender en sobrecompra sí está permitido. Estos niveles deben ser `input` configurables.
3. **Solo al cierre de vela**: la lógica de entrada/señal se evalúa una única vez por vela nueva, nunca en cada tick. Usar detección de nueva barra vía `iTime(_Symbol, _Period, 0)` comparado contra una variable estática/miembro, NUNCA `IsNewBar()` ad-hoc mal implementado ni time-based polling.
4. **Una sola operación abierta a la vez**: antes de evaluar o enviar una nueva entrada, verificar que no exista ya una posición abierta (`PositionSelect(_Symbol)` o, si el EA opera multi-símbolo/multi-magic, filtrar por symbol+magic). Si hay una posición abierta, no se evalúa ni envía ninguna orden nueva hasta cerrarla.

## Arquitectura obligatoria

- **POO real**, no scripts procedurales sueltos. Estructura mínima de clases:
  - `CSignalFilter` o similar: encapsula volumen + RSI, expone `bool IsAllowedToTrade()`.
  - `CBarMonitor`: encapsula detección de vela nueva.
  - `CExpertAdvisor` (o nombre del EA): orquesta, contiene `OnTick`, `OnInit`, `OnDeinit`, delega en los filtros y en `CTrade`.
- **`CTrade` nativo** (`#include <Trade\Trade.mqh>`) para toda ejecución de órdenes. Nunca `OrderSend` legacy MQL4-style.
- **Manejo exhaustivo de errores**: verificar `GetLastError()` / `ResultRetcode()` tras cada llamada de trading; verificar que los handles de indicadores (`iRSI`, etc.) sean distintos de `INVALID_HANDLE` en `OnInit`; verificar `CopyBuffer`/`CopyTickVolume` devuelvan `>0` antes de usar el array.
- **Buffers e indicadores**: crear los handles UNA sola vez en `OnInit` (nunca dentro de `OnTick`), liberar con `IndicatorRelease` en `OnDeinit`. Usar `ArraySetAsSeries(buffer, true)` sobre los arrays de `CopyBuffer`.
- **Inputs configurables**: volumen (período de promedio, default 20), RSI (período, niveles sobrecompra/sobreventa), lotaje/risk %, stop loss/take profit, trailing stop, magic number, slippage.
- **Comentarios descriptivos** en español, explicando el "por qué" de cada bloque no trivial (igual que en cualquier otro código del usuario) — no comentarios obvios.
- **Modularidad**: separar en archivos `.mqh` cuando el EA crezca (filtros, gestión de riesgo, trade manager), e incluirlos desde el `.mq5` principal.

## Plantilla de referencia

Usa `references/ea_template.mq5` como esqueleto base: incluye `CBarMonitor`, `CSignalFilter` (volumen + RSI) y `CExpertAdvisor` con `CTrade`, manejo de errores y las 3 reglas por defecto ya implementadas. Adapta la señal de entrada (`CSignalFilter::GetDirection`) a la estrategia específica que pida el usuario — el filtro de volumen/RSI/cierre-de-vela se mantiene como capa previa obligatoria, no como la señal misma.

## Al desviarse de las reglas por defecto

Si el usuario pide explícitamente omitir volumen, RSI, o operar en cada tick, respétalo — pero dilo explícitamente en un comentario en el código y, si es ambiguo si quiere desactivar una sola regla o las tres, pregunta antes de asumir.
