defmodule Trivia.Partida do
  @moduledoc "Una partida independiente, supervisada, con rondas, respuestas y bots."
  use GenServer, restart: :transient

  def start_link(opciones), do: GenServer.start_link(__MODULE__, opciones)
  def agregar_bot(pid, dificultad), do: GenServer.call(pid, {:agregar_bot, dificultad})
  def comenzar(pid), do: GenServer.call(pid, :comenzar)
  def responder(pid, usuario, letra, token \\ nil),
    do: GenServer.call(pid, {:responder, usuario, letra, token})
  def usar_comodin(pid, usuario, tipo, token),
    do: GenServer.call(pid, {:comodin, usuario, tipo, token})
  def abandonar(pid), do: GenServer.call(pid, :abandonar)

  def opciones_5050(opciones, correcta) do
    incorrectas = Enum.filter(["A", "B", "C", "D"], fn letra -> letra != correcta end)
    otra = Enum.random(incorrectas)
    %{correcta => Map.fetch!(opciones, correcta), otra => Map.fetch!(opciones, otra)}
  end
end
