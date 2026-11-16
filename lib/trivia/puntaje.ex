defmodule Trivia.Puntaje do
  @moduledoc "Reglas puras de puntuación; los tiempos se expresan en milisegundos."

  def calcular(_nivel, nil, _correcta, _restantes_ms, _total_ms), do: 0

  def calcular(nivel, letra, correcta, restantes_ms, total_ms)
      when total_ms > 0 and restantes_ms >= 0 do
    if letra == correcta do
      base = puntos_correctos(nivel)
      bonificacion = trunc(5 * min(restantes_ms, total_ms) / total_ms)
      base + bonificacion
    else
      puntos_incorrectos(nivel)
    end
  end

  def calcular_con_comodines(nivel, letra, correcta, restantes_ms, total_ms, sin_bono, doble) do
    tiempo = if sin_bono, do: 0, else: restantes_ms
    puntos = calcular(nivel, letra, correcta, tiempo, total_ms)
    if doble, do: puntos * 2, else: puntos
  end

  defp puntos_correctos("basico"), do: 10
  defp puntos_correctos("intermedio"), do: 15
  defp puntos_correctos("avanzado"), do: 20

  defp puntos_incorrectos("basico"), do: -5
  defp puntos_incorrectos("intermedio"), do: -8
  defp puntos_incorrectos("avanzado"), do: -10
end
