defmodule Trivia.Nivel do
  @moduledoc "Nivel, reparto de preguntas y estadísticas calculadas desde el historial."

  def desde_puntos(puntos) when puntos < 60, do: "basico"
  def desde_puntos(puntos) when puntos < 180, do: "intermedio"
  def desde_puntos(_puntos), do: "avanzado"

  def reparto("basico", total), do: calcular_reparto(total, "basico", 0, 30, 0)
  def reparto("intermedio", total), do: calcular_reparto(total, "intermedio", 20, 0, 20)
  def reparto("avanzado", total), do: calcular_reparto(total, "avanzado", 0, 30, 0)

  # Primero se truncan las cantidades ajenas al nivel del creador.
  # El sobrante se asigna enteramente al nivel del creador.
  defp calcular_reparto(total, principal, pct_basico, pct_intermedio, pct_avanzado) do
    basico = trunc(total * pct_basico / 100)
    intermedio = trunc(total * pct_intermedio / 100)
    avanzado = trunc(total * pct_avanzado / 100)
    sobrante = total - basico - intermedio - avanzado
    cantidades = %{"basico" => basico, "intermedio" => intermedio, "avanzado" => avanzado}
    Map.update!(cantidades, principal, fn cantidad -> cantidad + sobrante end)
  end

  def estadisticas(historial, usuario) do
    Enum.reduce(historial, %{puntaje: 0, partidas: 0, temas: %{}}, fn resultado, datos ->
      puntajes = Map.get(resultado, "puntajes", %{})

      case Map.fetch(puntajes, usuario) do
        {:ok, puntaje} ->
          tema = Map.get(resultado, "tema", "")
          temas = Map.update(datos.temas, tema, puntaje, fn previo -> previo + puntaje end)
          %{datos | puntaje: datos.puntaje + puntaje, partidas: datos.partidas + 1, temas: temas}

        :error ->
          datos
      end
    end)
  end

  def nivel_usuario(historial, usuario, tema) do
    datos = estadisticas(historial, usuario)
    desde_puntos(Map.get(datos.temas, tema, 0))
  end

  def ranking(historial, tema \\ nil) do
    historial
    |> Enum.filter(fn resultado -> tema == nil or Map.get(resultado, "tema") == tema end)
    |> Enum.reduce(%{}, fn resultado, acumulado ->
      resultado
      |> Map.get("puntajes", %{})
      |> Enum.reduce(acumulado, fn {usuario, puntos}, datos ->
        if String.starts_with?(usuario, "bot_") do
          datos
        else
          Map.update(datos, usuario, %{puntaje: puntos, partidas: 1}, fn previo ->
            %{puntaje: previo.puntaje + puntos, partidas: previo.partidas + 1}
          end)
        end
      end)
    end)
    |> Enum.sort_by(fn {usuario, datos} -> {-datos.puntaje, usuario} end)
  end
end

