defmodule Trivia.Bot do
  @moduledoc "Bot enlazado a su partida, que recibe preguntas y responde luego de un retardo."

  def iniciar(nombre, dificultad) do
    spawn_link(fn -> escuchar(nombre, dificultad, nil) end)
  end

  def decision(dificultad, nivel, correcta, tiempo_ms) do
    probabilidad = probabilidad(dificultad, nivel)
    acierta = :rand.uniform() <= probabilidad

    letra =
      if acierta do
        correcta
      else
        ["A", "B", "C", "D"]
        |> Enum.reject(fn opcion -> opcion == correcta end)
        |> Enum.random()
      end

    {inicio, fin} = rango_tiempo(dificultad)
    fraccion = inicio + :rand.uniform() * (fin - inicio)
    retraso = trunc(fraccion * tiempo_ms)
    {letra, max(1, retraso)}
  end

  defp probabilidad("facil", "basico"), do: 0.4
  defp probabilidad("facil", "intermedio"), do: 0.3
  defp probabilidad("facil", "avanzado"), do: 0.2
  defp probabilidad("dificil", "basico"), do: 0.8
  defp probabilidad("dificil", "intermedio"), do: 0.7
  defp probabilidad("dificil", "avanzado"), do: 0.6

  defp rango_tiempo("facil"), do: {0.4, 0.9}
  defp rango_tiempo("dificil"), do: {0.1, 0.4}

  defp escuchar(nombre, dificultad, temporizador) do
    receive do
      {:trivia, :pregunta, pregunta} ->
        if temporizador != nil, do: Process.cancel_timer(temporizador)
        {letra, retraso} = decision(dificultad, pregunta.nivel, pregunta.respuesta, pregunta.tiempo_ms)
        nuevo = Process.send_after(self(), {:contestar, pregunta.partida, letra, pregunta.token}, retraso)
        escuchar(nombre, dificultad, nuevo)

      {:contestar, partida, letra, token} ->
        # Misma API de respuesta para humanos y bots; la partida valida el token.
        Trivia.Partida.responder(partida, nombre, letra, token)
        escuchar(nombre, dificultad, nil)

      {:trivia, :cierre, _datos} ->
        if temporizador != nil, do: Process.cancel_timer(temporizador)
        escuchar(nombre, dificultad, nil)

      {:trivia, :fin, _datos} ->
        if temporizador != nil, do: Process.cancel_timer(temporizador)
        :ok

      {:trivia, :aviso, _texto} ->
        escuchar(nombre, dificultad, temporizador)

      :detener ->
        :ok
    end
  end
end
