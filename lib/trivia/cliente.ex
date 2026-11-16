defmodule Trivia.Cliente do
  @moduledoc "Interfaz de consola sin datos ni lógica de juego en el cliente."

  def iniciar do
    if node() == :nonode@nohost do
      IO.puts("Debes iniciar IEx con --sname, por ejemplo: iex --sname pedro -S mix")
    else
      receptor = Trivia.Receptor.iniciar()
      IO.puts("Trivia Concurrente. Escribe help para ver los comandos.")
      leer(receptor)
    end
  end
end
