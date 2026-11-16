defmodule Trivia.Bot do
  @moduledoc "Bot enlazado a su partida, que recibe preguntas y responde luego de un retardo."

  def iniciar(nombre, dificultad) do
    spawn_link(fn -> escuchar(nombre, dificultad, nil) end)
  end

  defp escuchar(nombre, dificultad, temporizador) do
    receive do
      :detener -> :ok
    end
  end
end
