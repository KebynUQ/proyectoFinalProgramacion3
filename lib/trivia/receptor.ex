defmodule Trivia.Receptor do
  @moduledoc "Proceso del cliente que imprime notificaciones sin bloquear el teclado."

  def iniciar do
    spawn_link(fn -> escuchar(nil) end)
  end

  defp escuchar(token) do
    receive do
      {:trivia, :pregunta, datos} ->
        lineas =
          [
            "\n═══ Pregunta #{datos.numero} de #{datos.total} - #{datos.tema} - #{datos.nivel} ═══",
            datos.enunciado
          ] ++
            opciones_texto(datos.opciones) ++
            ["Tiempo: #{datos.tiempo} segundos. Responde: answer A/B/C/D\n"]

        IO.puts(Enum.join(lineas, "\n"))
        escuchar(datos.token)

      {:trivia, :pregunta_5050, datos} ->
        lineas =
          [
            "\n═══ Comodín 50/50 - Pregunta #{datos.numero} de #{datos.total} ═══",
            "Bonificación por rapidez: 0 en esta ronda",
            datos.enunciado
          ] ++
            opciones_texto(datos.opciones) ++
            ["Tiempo restante: #{datos.tiempo_restante_ms} ms. Responde: answer A/B/C/D\n"]

        IO.puts(Enum.join(lineas, "\n"))
        escuchar(datos.token)

      {:trivia, :cierre, datos} ->
        IO.puts("\n--- Fin de la ronda #{datos.ronda} ---")
        IO.puts("Respuesta correcta: #{datos.correcta}) #{datos.opcion}")

        Enum.each(datos.resultados, fn fila ->
          IO.puts("#{fila.nombre}: #{fila.cambio} (total: #{fila.total})")
        end)

        escuchar(nil)

      {:trivia, :fin, datos} ->
        IO.puts("\n═══ Fin de la partida #{datos.id} (#{datos.tema}, #{datos.nivel}) ═══")

        datos.ranking
        |> Enum.with_index(1)
        |> Enum.each(fn {{usuario, puntos}, puesto} ->
          IO.puts("#{puesto}. #{usuario}: #{puntos} puntos")
        end)

        IO.puts("Ganador(es): #{Enum.join(datos.ganadores, ", ")}")
        if datos.guardado != :ok, do: IO.puts("ADVERTENCIA: no se pudo persistir el resultado")
        escuchar(nil)

      {:trivia, :aviso, texto} ->
        IO.puts("\nAVISO: #{texto}")
        escuchar(token)

      {:ronda_actual, solicitante, referencia} ->
        send(solicitante, {referencia, token})
        escuchar(token)

      :detener ->
        :ok
    end
  end

  defp opciones_texto(opciones) do
    ["A", "B", "C", "D"]
    |> Enum.filter(fn letra -> Map.has_key?(opciones, letra) end)
    |> Enum.map(fn letra -> "#{letra}) #{Map.fetch!(opciones, letra)}" end)
  end
end
